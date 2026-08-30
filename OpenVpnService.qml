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
  property var connectionInfo: ({})
  property bool nmcliAvailable: true

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

  // Set while a blank submission is in flight, so the helper's "credentials
  // required" complaint never reaches the panel: that attempt is speculative
  // and its failure is answered by opening the prompt, not by an error.
  // Set while the panel is collecting credentials to hand to NetworkManager
  // for keeping, rather than to use for this one activation.
  property bool rememberCredentials: false
  property bool silentConnect: false
  property string silentUuid: ""
  property string silentName: ""

  signal authenticationFailed()
  signal authenticationPrompted()

  function boundedText(value, limit) {
    var result = String(value || "")
    return result.length > limit ? result.substring(0, limit) : result
  }

  function setError(value) {
    lastError = boundedText(value, 4096).trim()
  }

  function finalizeList() {
    if (listExitCode === null || !listStreamFinished) return
    nmcliAvailable = listExitCode === 0
    if (listExitCode === 0) {
      profiles = parseProfiles(listOutput)
      if (authUuid === "" && !actionProcess.running && !importProcess.running) setError("")
      refreshDetails()
    } else if (listTimedOut) {
      setError("NetworkManager inventory timed out.")
    } else {
      setError(listOutput === "" ? "Could not query NetworkManager profiles." : listOutput)
    }
  }

  function finalizeDetails() {
    if (detailsExitCode === null || !detailsStreamFinished) return
    if (detailsExitCode === 0) parseDetails(detailsOutput)
    else if (detailsTimedOut) setError("Connection details timed out.")
    else setError(detailsOutput === "" ? "Could not query connection details." : detailsOutput)
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
        connecting: fields[4] === "activating"
      })
    }
    result.sort(function(a, b) {
      if (a.active !== b.active) return a.active ? -1 : 1
      return String(a.name).localeCompare(String(b.name))
    })
    return result
  }

  function refresh() {
    if (queryHelper === "") return
    if (!listProcess.running) {
      listOutput = ""
      listTimedOut = false
      listExitCode = null
      listStreamFinished = false
      listProcess.command = [queryHelper, "list"]
      listProcess.running = true
    }
  }

  function setConnection(profile, helperPath) {
    if (!profile || profile.connecting || actionProcess.running || authProcess.running) return false
    if (!profile.active) {
      authUuid = ""
      authName = ""
      authUsername = ""
      authPassword = ""
      setError("")
      // NetworkManager may already hold everything this profile needs. Ask the
      // helper to activate it with no credentials; it answers with exit code 2
      // when a prompt really is required, and openAuthentication() takes over.
      if (helperPath && helperPath !== "") {
        silentConnect = true
        silentUuid = profile.uuid
        silentName = profile.name
        busyUuid = profile.uuid
        authProcess.input = "\n\n"
        authProcess.command = [helperPath, profile.uuid]
        authProcess.running = true
        return false
      }
      rememberCredentials = false
      openAuthentication(profile.uuid, profile.name)
      return true
    }
    busyUuid = profile.uuid
    setError("")
    actionProcess.command = ["nmcli", "connection", "down", "uuid", profile.uuid]
    actionProcess.running = true
    return false
  }

  function openAuthentication(uuid, name) {
    authUuid = uuid
    authName = name
    authUsername = ""
    authPassword = ""
  }

  function editCredentials(profile) {
    if (!profile || actionProcess.running || authProcess.running) return false
    setError("")
    openAuthentication(profile.uuid, profile.name)
    rememberCredentials = true
    return true
  }

  function cancelAuthentication() {
    rememberCredentials = false
    silentConnect = false
    authUuid = ""
    authName = ""
    authUsername = ""
    authPassword = ""
    setError("")
  }

  function submitAuthentication(helperPath) {
    if (authUuid === "" || authProcess.running) return
    // A fully blank submission is how certificate-only (connection-type=tls)
    // profiles connect; the helper re-checks the profile type before acting.
    // A half-filled form is still rejected.
    var blank = authUsername.trim() === "" && authPassword === ""
    if (rememberCredentials && blank) return
    if (!blank && (authUsername.trim() === "" || authPassword === "")) return
    busyUuid = authUuid
    silentConnect = false
    setError("")
    authProcess.input = authUsername.replace(/[\r\n]/g, "") + "\n" + authPassword.replace(/[\r\n]/g, "") + "\n"
    authProcess.command = rememberCredentials ? [helperPath, authUuid, "--remember"] : [helperPath, authUuid]
    authProcess.running = true
  }

  function renameConnection(uuid, nextName) {
    if (uuid === "" || nextName === "" || actionProcess.running) return
    busyUuid = uuid
    setError("")
    actionProcess.command = ["nmcli", "connection", "modify", "uuid", uuid, "connection.id", nextName]
    actionProcess.running = true
  }

  function deleteConnection(uuid) {
    if (uuid === "" || actionProcess.running) return
    busyUuid = uuid
    setError("")
    actionProcess.command = ["nmcli", "connection", "delete", "uuid", uuid]
    actionProcess.running = true
  }

  function importProfile(helperPath) {
    if (importProcess.running) return
    setError("")
    importProcess.command = [helperPath]
    importProcess.running = true
  }

  function parseDetails(text) {
    var info = ({})
    var lines = String(text || "").trim().split(/\r?\n/)
    for (var i = 0; i < lines.length; i++) {
      var at = lines[i].indexOf(":")
      if (lines[i].length > 4096) continue
      if (at > 0) {
        var key = boundedField(lines[i].substring(0, at), 128)
        info[key] = boundedField(lines[i].substring(at + 1).replace(/\\:/g, ":"), 1024)
      }
    }
    connectionInfo = info
  }

  function refreshDetails() {
    var active = null
    for (var i = 0; i < profiles.length; i++) {
      if (profiles[i].active) { active = profiles[i]; break }
    }
    if (!active) { connectionInfo = ({}); return }
    if (!detailsProcess.running) {
      detailsOutput = ""
      detailsTimedOut = false
      detailsExitCode = null
      detailsStreamFinished = false
      detailsProcess.command = [queryHelper, "details", active.uuid]
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
      service.busyUuid = ""
      if (code !== 0 && service.lastError !== "") console.warn("openvpn-widget", service.lastError)
      refreshDelay.restart()
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
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: { if (!service.silentConnect) service.setError(text) } }
    onExited: function(code) {
      service.busyUuid = ""
      if (service.silentConnect) {
        var uuid = service.silentUuid
        var name = service.silentName
        service.silentUuid = ""
        service.silentName = ""
        if (code === 0) {
          service.silentConnect = false
          service.cancelAuthentication()
        } else {
          // Leave silentConnect set until the prompt is on screen so a late
          // stderr stream cannot flash the helper's complaint at the user.
          service.rememberCredentials = false
          service.openAuthentication(uuid, name)
          service.authenticationPrompted()
        }
      } else if (code === 0) {
        service.cancelAuthentication()
      } else {
        service.authenticationFailed()
      }
      refreshDelay.restart()
    }
  }

  Timer { interval: service.refreshInterval; running: true; repeat: true; triggeredOnStart: true; onTriggered: service.refresh() }
  Timer { id: refreshDelay; interval: 700; onTriggered: service.refresh() }
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
