import QtQuick
import Quickshell.Io

Item {
  id: service
  visible: false

  property string configuredName: ""
  property int refreshInterval: 5000
  property string queryHelper: ""
  property var profiles: []
  property string lastError: ""
  property string busyUuid: ""
  property string authUuid: ""
  property string authName: ""
  property string authUsername: ""
  property string authPassword: ""
  // uuid -> { state, device, address, gateway, dns } for every connected profile.
  property var connectionDetails: ({})
  property bool nmcliAvailable: true
  // When false, connecting a VPN disconnects the others first.
  property bool allowSeveralConnections: true
  // What the running panel action does to busyUuid: "connect", "disconnect",
  // "rename" or "delete".
  property string busyAction: ""
  // The action has ended; busy stays until a list started after that arrives.
  property bool busySettling: false
  property bool listAfterAction: false
  property real settleStartedAt: 0
  // How long a busy state may sit with nothing running before it is released.
  readonly property int busyWatchdogMs: 10000
  // lastError came from a failed inventory or details query, which the next
  // successful list clears. Action errors stay until the next action.
  property bool listErrorShown: false

  property string listOutput: ""
  property string detailsOutput: ""
  property bool listTimedOut: false
  property bool detailsTimedOut: false
  property var listExitCode: null
  property bool listStreamFinished: false
  property var detailsExitCode: null
  property bool detailsStreamFinished: false

  readonly property bool actionRunning: actionProcess.running
  readonly property bool authenticationRunning: authProcess.running
  readonly property bool importRunning: importProcess.running

  signal authenticationFailed()

  function boundedText(value, limit) {
    var result = String(value || "")
    return result.length > limit ? result.substring(0, limit) : result
  }

  function setError(value) {
    lastError = boundedText(value, 4096).trim()
    listErrorShown = false
  }

  function setListError(value) {
    setError(value)
    listErrorShown = true
  }

  function finalizeList() {
    if (listExitCode === null || !listStreamFinished) return
    nmcliAvailable = listExitCode === 0
    if (listExitCode === 0) {
      profiles = parseProfiles(listOutput)
      if (listErrorShown) setError("")
      refreshDetails()
    } else if (listTimedOut) {
      setListError("NetworkManager inventory timed out.")
    } else {
      setListError(listOutput === "" ? "Could not query NetworkManager profiles." : listOutput)
    }
    // A list that started before the action ended still shows the old state,
    // so keep the action's status until a newer list arrives.
    if (busySettling) {
      if (listAfterAction) clearBusy()
      else refreshDelay.restart()
    }
  }

  function finalizeDetails() {
    if (detailsExitCode === null || !detailsStreamFinished) return
    // On failure the last known details stay; the next refresh replaces them.
    if (detailsExitCode === 0) connectionDetails = parseDetails(detailsOutput)
    else if (detailsTimedOut) setListError("Connection details timed out.")
    else setListError(detailsOutput === "" ? "Could not query connection details." : detailsOutput)
  }

  function boundedField(value, limit) {
    return boundedText(value, limit).replace(/[\u0000-\u001f\u007f]/g, "")
  }

  function splitNmcliRow(line) {
    var fields = []
    var field = ""
    var escaped = false
    var value = String(line || "")
    for (var i = 0; i < value.length; i++) {
      var c = value.charAt(i)
      if (escaped) { field += c; escaped = false }
      else if (c === "\\") escaped = true
      else if (c === ":") { fields.push(field); field = "" }
      else field += c
    }
    if (escaped) field += "\\"
    fields.push(field)
    return fields
  }

  function parseProfiles(text) {
    var result = []
    var lines = String(text || "").trim().split(/\r?\n/)
    for (var i = 0; i < lines.length && result.length < 256; i++) {
      if (lines[i].length > 4096) continue
      var fields = splitNmcliRow(lines[i])
      if (fields.length < 5 || fields[2] !== "vpn") continue
      if (configuredName !== "" && fields[1] !== configuredName) continue
      result.push({
        uuid: boundedField(fields[0], 64),
        name: boundedField(fields[1], 512),
        device: boundedField(fields[3], 128),
        state: boundedField(fields[4], 64),
        active: fields[4] === "activated",
        connecting: fields[4] === "activating",
        disconnecting: fields[4] === "deactivating"
      })
    }
    // Name order only: with several VPNs up, moving connected rows to the top
    // would shift the row that was just clicked.
    result.sort(function(a, b) { return String(a.name).localeCompare(String(b.name)) })
    return result
  }

  function refresh() {
    if (queryHelper === "") return
    if (!listProcess.running) {
      listOutput = ""
      listTimedOut = false
      listExitCode = null
      listStreamFinished = false
      listAfterAction = busySettling
      listProcess.command = [queryHelper, "list"]
      listProcess.running = true
    }
  }

  function setConnection(profile) {
    if (!profile || profile.connecting || actionProcess.running || authProcess.running) return false
    if (!profile.active) {
      authUuid = profile.uuid
      authName = profile.name
      authUsername = ""
      authPassword = ""
      setError("")
      return true
    }
    startBusy(profile.uuid, "disconnect")
    setError("")
    actionProcess.command = ["nmcli", "connection", "down", "uuid", profile.uuid]
    actionProcess.running = true
    return false
  }

  function cancelAuthentication() {
    authUuid = ""
    authName = ""
    authUsername = ""
    authPassword = ""
    setError("")
  }

  function submitAuthentication(helperPath) {
    if (authUuid === "" || authProcess.running || actionProcess.running) return
    // A fully blank submission is how certificate-only (connection-type=tls)
    // profiles connect; the helper re-checks the profile type before acting.
    // A half-filled form is still rejected.
    var blank = authUsername.trim() === "" && authPassword === ""
    if (!blank && (authUsername.trim() === "" || authPassword === "")) return
    startBusy(authUuid, "connect")
    setError("")
    authProcess.input = authUsername.replace(/[\r\n]/g, "") + "\n" + authPassword.replace(/[\r\n]/g, "") + "\n"
    authProcess.command = connectCommand(helperPath, authUuid)
    authProcess.running = true
  }

  function renameConnection(uuid, nextName) {
    if (uuid === "" || nextName === "" || actionProcess.running) return
    startBusy(uuid, "rename")
    setError("")
    actionProcess.command = ["nmcli", "connection", "modify", "uuid", uuid, "connection.id", nextName]
    actionProcess.running = true
  }

  // The delete helper disconnects a connected profile before deleting it.
  function deleteConnection(uuid, helperPath) {
    if (uuid === "" || actionProcess.running) return
    startBusy(uuid, "delete")
    setError("")
    actionProcess.command = [helperPath, uuid]
    actionProcess.running = true
  }

  // A new action replaces one that is still settling.
  function startBusy(uuid, action) {
    busyUuid = uuid
    busyAction = action
    busySettling = false
  }

  function settleAction() {
    busySettling = true
    settleStartedAt = Date.now()
    refreshDelay.restart()
  }

  // Safety net: busy with no process running, and no refresh pending for a
  // whole watchdog period, means a helper never started or never reported its
  // exit. Release it so the switches do not stay disabled until a restart.
  function releaseStuckBusy(now) {
    if (busyUuid === "" || actionProcess.running || authProcess.running) return false
    if (busySettling && now - settleStartedAt < busyWatchdogMs) return false
    console.warn("openvpn-widget", "released a busy state that no action ended")
    clearBusy()
    return true
  }

  function clearBusy() {
    busyUuid = ""
    busyAction = ""
    busySettling = false
  }

  // Status line under a profile name; a running panel action wins over the
  // state NetworkManager last reported.
  function profileStatus(profile) {
    if (profile.uuid === busyUuid) {
      if (busyAction === "connect") return "Connecting…"
      if (busyAction === "disconnect") return "Disconnecting…"
      if (busyAction === "delete") return "Deleting…"
    }
    if (profile.disconnecting) return "Disconnecting…"
    if (profile.connecting) return "Connecting…"
    return profile.active ? "Connected" : "Disconnected"
  }

  // The switch shows where a running action is heading.
  function profileSwitchOn(profile) {
    if (profile.uuid === busyUuid) {
      if (busyAction === "connect") return true
      if (busyAction === "disconnect") return false
    }
    return profile.active || profile.connecting
  }

  function connectCommand(helperPath, uuid) {
    var command = [helperPath, uuid]
    if (!allowSeveralConnections) command.push("--exclusive")
    return command
  }

  // A boolean setting may arrive as a string: omarchy bar set stores one
  // unless given --json.
  function settingFlag(value, fallback) {
    if (value === true || value === false) return value
    var text = String(value === undefined || value === null ? "" : value).trim().toLowerCase()
    if (text === "true") return true
    if (text === "false") return false
    return fallback
  }

  function importProfile(helperPath) {
    if (importProcess.running) return
    setError("")
    importProcess.command = [helperPath]
    importProcess.running = true
  }

  // nmcli prints one block per connection, each starting with GENERAL.UUID.
  function parseDetails(text) {
    var raw = ({})
    var current = null
    var lines = String(text || "").trim().split(/\r?\n/)
    for (var i = 0; i < lines.length; i++) {
      var at = lines[i].indexOf(":")
      if (lines[i].length > 4096 || at <= 0) continue
      var key = boundedField(lines[i].substring(0, at), 128)
      var value = boundedField(lines[i].substring(at + 1).replace(/\\:/g, ":"), 1024)
      if (key === "GENERAL.UUID") current = raw[value] = ({})
      else if (current) current[key] = value
    }
    var details = ({})
    for (var uuid in raw) {
      var info = raw[uuid]
      details[uuid] = {
        state: info["GENERAL.STATE"] || "",
        device: info["GENERAL.DEVICES"] || "",
        address: info["IP4.ADDRESS[1]"] || info["IP4.ADDRESS"] || "",
        gateway: info["IP4.GATEWAY"] || "",
        dns: info["IP4.DNS[1]"] || info["IP4.DNS"] || ""
      }
    }
    return details
  }

  function activeUuids() {
    var result = []
    for (var i = 0; i < profiles.length; i++) if (profiles[i].active) result.push(profiles[i].uuid)
    return result
  }

  function refreshDetails() {
    var uuids = activeUuids()
    if (uuids.length === 0) { connectionDetails = ({}); return }
    if (!detailsProcess.running) {
      detailsOutput = ""
      detailsTimedOut = false
      detailsExitCode = null
      detailsStreamFinished = false
      detailsProcess.command = [queryHelper, "details"].concat(uuids)
      detailsProcess.running = true
    }
  }

  Process {
    id: listProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        service.listOutput = service.boundedText(text, 262144)
        service.listStreamFinished = true
        service.finalizeList()
      }
    }
    onStarted: listDeadline.restart()
    onExited: function(code) {
      listDeadline.stop()
      listKillDelay.stop()
      service.listExitCode = code
      service.finalizeList()
    }
  }

  Process {
    id: actionProcess
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: service.setError(text) }
    onExited: function(code) {
      if (code !== 0 && service.lastError !== "") console.warn("openvpn-widget", service.lastError)
      service.settleAction()
    }
  }

  Process {
    id: detailsProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        service.detailsOutput = service.boundedText(text, 262144)
        service.detailsStreamFinished = true
        service.finalizeDetails()
      }
    }
    stderr: StdioCollector { waitForEnd: true }
    onStarted: detailsDeadline.restart()
    onExited: function(code) {
      detailsDeadline.stop()
      detailsKillDelay.stop()
      service.detailsExitCode = code
      service.finalizeDetails()
    }
  }

  Process {
    id: importProcess
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: service.setError(text) }
    onExited: function(code) {
      if (code === 1) service.setError("")
      refreshDelay.restart()
    }
  }

  Process {
    id: authProcess
    property string input: ""
    stdinEnabled: true
    onStarted: {
      write(input)
      input = ""
      service.authPassword = ""
    }
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: service.setError(text) }
    onExited: function(code) {
      if (code === 0) service.cancelAuthentication()
      else service.authenticationFailed()
      service.settleAction()
    }
  }

  Timer { interval: service.refreshInterval; running: true; repeat: true; triggeredOnStart: true; onTriggered: service.refresh() }
  Timer { id: refreshDelay; interval: 700; onTriggered: service.refresh() }
  Timer {
    interval: service.busyWatchdogMs
    repeat: true
    running: service.busyUuid !== ""
    onTriggered: service.releaseStuckBusy(Date.now())
  }
  Timer {
    id: listDeadline
    interval: 6000
    onTriggered: {
      if (!listProcess.running) return
      service.listTimedOut = true
      listProcess.signal(15)
      listKillDelay.restart()
    }
  }
  Timer { id: listKillDelay; interval: 1000; onTriggered: if (listProcess.running) listProcess.signal(9) }
  Timer {
    id: detailsDeadline
    interval: 6000
    onTriggered: {
      if (!detailsProcess.running) return
      service.detailsTimedOut = true
      detailsProcess.signal(15)
      detailsKillDelay.restart()
    }
  }
  Timer { id: detailsKillDelay; interval: 1000; onTriggered: if (detailsProcess.running) detailsProcess.signal(9) }
}
