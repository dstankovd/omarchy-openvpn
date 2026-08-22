import QtQuick
import Quickshell.Io

Item {
  id: service
  visible: false

  property string configuredName: ""
  property int refreshInterval: 5000
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

  readonly property bool actionRunning: actionProcess.running
  readonly property bool authenticationRunning: authProcess.running
  readonly property bool importRunning: importProcess.running

  signal authenticationFailed()

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
    for (var i = 0; i < lines.length; i++) {
      var fields = splitNmcliRow(lines[i])
      if (fields.length < 5 || fields[2] !== "vpn") continue
      if (configuredName !== "" && fields[1] !== configuredName) continue
      result.push({
        uuid: fields[0],
        name: fields[1],
        device: fields[3],
        state: fields[4],
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
    if (!listProcess.running) {
      listOutput = ""
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
      lastError = ""
      return true
    }
    busyUuid = profile.uuid
    lastError = ""
    actionProcess.command = ["nmcli", "connection", "down", "uuid", profile.uuid]
    actionProcess.running = true
    return false
  }

  function cancelAuthentication() {
    authUuid = ""
    authName = ""
    authUsername = ""
    authPassword = ""
    lastError = ""
  }

  function submitAuthentication(helperPath) {
    if (authUuid === "" || authUsername.trim() === "" || authPassword === "" || authProcess.running) return
    busyUuid = authUuid
    lastError = ""
    authProcess.input = authUsername.replace(/[\r\n]/g, "") + "\n" + authPassword.replace(/[\r\n]/g, "") + "\n"
    authProcess.command = [helperPath, authUuid]
    authProcess.running = true
  }

  function renameConnection(uuid, nextName) {
    if (uuid === "" || nextName === "" || actionProcess.running) return
    busyUuid = uuid
    lastError = ""
    actionProcess.command = ["nmcli", "connection", "modify", "uuid", uuid, "connection.id", nextName]
    actionProcess.running = true
  }

  function deleteConnection(uuid) {
    if (uuid === "" || actionProcess.running) return
    busyUuid = uuid
    lastError = ""
    actionProcess.command = ["nmcli", "connection", "delete", "uuid", uuid]
    actionProcess.running = true
  }

  function importProfile(helperPath) {
    if (importProcess.running) return
    lastError = ""
    importProcess.command = [helperPath]
    importProcess.running = true
  }

  function parseDetails(text) {
    var info = ({})
    var lines = String(text || "").trim().split(/\r?\n/)
    for (var i = 0; i < lines.length; i++) {
      var at = lines[i].indexOf(":")
      if (at > 0) info[lines[i].substring(0, at)] = lines[i].substring(at + 1).replace(/\\:/g, ":")
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
      detailsProcess.command = ["nmcli", "-t", "-f", "GENERAL.NAME,GENERAL.STATE,GENERAL.DEVICES,IP4.ADDRESS,IP4.GATEWAY,IP4.DNS", "connection", "show", "uuid", active.uuid]
      detailsProcess.running = true
    }
  }

  Process {
    id: listProcess
    command: ["nmcli", "-t", "--escape", "yes", "-f", "UUID,NAME,TYPE,DEVICE,STATE", "connection", "show"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: service.listOutput = text }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (String(text || "").trim() !== "") service.lastError = String(text).trim()
    }
    onExited: function(code) {
      service.nmcliAvailable = code === 0
      if (code === 0) {
        service.profiles = service.parseProfiles(service.listOutput)
        if (service.authUuid === "" && !actionProcess.running && !importProcess.running) service.lastError = ""
        service.refreshDetails()
      }
    }
  }

  Process {
    id: actionProcess
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: service.lastError = String(text || "").trim() }
    onExited: function(code) {
      service.busyUuid = ""
      if (code !== 0 && service.lastError !== "") console.warn("openvpn-widget", service.lastError)
      refreshDelay.restart()
    }
  }

  Process {
    id: detailsProcess
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: service.detailsOutput = text }
    onExited: function(code) { if (code === 0) service.parseDetails(service.detailsOutput) }
  }

  Process {
    id: importProcess
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: service.lastError = String(text || "").trim() }
    onExited: function(code) {
      if (code === 1) service.lastError = ""
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
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: service.lastError = String(text || "").trim() }
    onExited: function(code) {
      service.busyUuid = ""
      if (code === 0) service.cancelAuthentication()
      else service.authenticationFailed()
      refreshDelay.restart()
    }
  }

  Timer { interval: service.refreshInterval; running: true; repeat: true; triggeredOnStart: true; onTriggered: service.refresh() }
  Timer { id: refreshDelay; interval: 700; onTriggered: service.refresh() }
}
