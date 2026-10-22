import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
// IpcHandler is provided by Quickshell.Io.
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "dimitar.openvpn"
  ipcTarget: "dimitar.openvpn"
  manageIpc: false

  readonly property var profiles: service.profiles
  readonly property string lastError: service.lastError
  readonly property string busyUuid: service.busyUuid
  property string pendingDeleteUuid: ""
  property string pendingDeleteName: ""
  readonly property string authUuid: service.authUuid
  readonly property string authName: service.authName
  property string renameUuid: ""
  property string renameOriginalName: ""
  property string renameName: ""
  readonly property var connectionDetails: service.connectionDetails
  readonly property bool nmcliAvailable: service.nmcliAvailable
  property bool settingsOpen: false
  property bool pendingDeleteConnected: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string configuredName: String(settings.connection || "").trim()
  readonly property bool allowSeveralConnections: service.settingFlag(settings.allowSeveralConnections, true)
  readonly property int connectedCount: {
    var count = 0
    for (var i = 0; i < profiles.length; i++) if (profiles[i].active) count++
    return count
  }
  readonly property string activeProfileNames: {
    var names = []
    for (var i = 0; i < profiles.length; i++) if (profiles[i].active) names.push(profiles[i].name)
    return names.join(", ")
  }
  readonly property string connectingProfileName: {
    for (var i = 0; i < profiles.length; i++) if (profiles[i].connecting) return profiles[i].name
    return ""
  }
  readonly property color iconColor: connectedCount > 0 ? foreground : dim
  readonly property string vpnIcon: "󰖂"
  readonly property string profileIcon: "󰌆"
  readonly property string heroStatus: !nmcliAvailable ? "NetworkManager unavailable"
    : connectedCount > 0 ? "Connected · " + activeProfileNames
    : connectingProfileName !== "" ? "Connecting · " + connectingProfileName
    : profiles.length > 0 ? "Disconnected" : "No VPN profiles found"
  readonly property int refreshInterval: Math.max(2, Math.min(300,
    parseInt(String(settings.refreshIntervalSec || 5), 10) || 5)) * 1000
  readonly property string tooltip: !nmcliAvailable ? "OpenVPN: NetworkManager unavailable"
    : connectedCount > 0 ? "OpenVPN: " + connectedCount + " active"
    : profiles.length > 0 ? "OpenVPN disconnected" : "OpenVPN: no profiles"

  function refresh() { service.refresh() }

  // Resolve bundled helpers from this QML file so the plugin works from any
  // user's plugin directory and from git checkouts with spaces in the path.
  function bundledPath(name) {
    return decodeURIComponent(String(Qt.resolvedUrl(name)).replace(/^file:\/\//, ""))
  }

  function setConnection(profile) {
    if (service.setConnection(profile)) {
      Qt.callLater(function() { usernameField.forceActiveFocus() })
    }
  }

  function cancelAuthentication() { service.cancelAuthentication() }

  function submitAuthentication() {
    service.submitAuthentication(bundledPath("connect-profile"))
  }

  function requestDelete(profile) {
    pendingDeleteUuid = profile.uuid
    pendingDeleteName = profile.name
    pendingDeleteConnected = profile.active || profile.connecting
  }

  function requestRename(profile) {
    cancelDelete()
    renameUuid = profile.uuid
    renameOriginalName = profile.name
    renameName = profile.name
    service.lastError = ""
    Qt.callLater(function() { renameField.forceActiveFocus(); renameField.selectAll() })
  }

  function cancelRename() {
    renameUuid = ""
    renameOriginalName = ""
    renameName = ""
  }

  function confirmRename() {
    var nextName = renameName.replace(/[\r\n]/g, "").trim()
    if (renameUuid === "" || nextName === "" || nextName === renameOriginalName || service.actionRunning) return
    service.renameConnection(renameUuid, nextName)
    cancelRename()
  }

  function cancelDelete() {
    pendingDeleteUuid = ""
    pendingDeleteName = ""
    pendingDeleteConnected = false
  }

  function confirmDelete() {
    if (pendingDeleteUuid === "" || service.actionRunning) return
    service.deleteConnection(pendingDeleteUuid, bundledPath("delete-profile"))
    cancelDelete()
  }

  function openImportPicker() {
    service.importProfile(bundledPath("import-profile"))
  }

  function openSettings() { cancelDelete(); settingsOpen = true }
  function closeSettings() { cancelDelete(); settingsOpen = false }

  // Escape steps back one level: the delete confirmation, then the settings
  // view, then the panel itself.
  function handleEscape() {
    if (pendingDeleteUuid !== "") cancelDelete()
    else if (settingsOpen) closeSettings()
    else root.close()
  }

  // updateEntryInline replaces the widget's whole entry, so merge the new
  // values into the current settings first, as the built-in panels do.
  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  onOpenedChanged: {
    if (opened) { refresh(); Qt.callLater(function() { keys.forceActiveFocus() }) }
    else { settingsOpen = false; cancelDelete() }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refresh(); return "ok" }
    function status(): string { return root.tooltip }
  }

  OpenVpnService {
    id: service
    allowSeveralConnections: root.allowSeveralConnections
    configuredName: root.configuredName
    refreshInterval: root.refreshInterval
    queryHelper: root.bundledPath("nmcli-query")
    onAuthenticationFailed: Qt.callLater(function() { passwordField.forceActiveFocus() })
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    slotSize: Style.bar.statusSlot
    tooltipText: root.tooltip
    iconComponent: Component {
      Item {
        Text {
          anchors.centerIn: parent
          text: root.vpnIcon
          color: root.iconColor
          opacity: root.connectedCount > 0 ? 1 : 0.55
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
        }
      }
    }
    onPressed: function(code) { if (code === Qt.LeftButton) root.toggle() }
  }

  // The dialogs float over the rows. The panel must be at least as tall as the
  // open dialog, or the dialog spills past the panel edges.
  readonly property real dialogHeight: authCard.visible ? authCard.height + Style.space(24)
    : renameCard.visible ? renameCard.height + Style.space(24)
    : deleteCard.visible ? deleteCard.height + Style.space(24) : 0

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keys
    contentWidth: panel.fittedContentWidth(Style.space(430))
    contentHeight: panel.fittedContentHeight(Math.max(content.implicitHeight, root.dialogHeight))

    PanelKeyCatcher {
      id: keys
      anchors.fill: parent
      blocked: root.authUuid !== "" || root.renameUuid !== ""
      onCloseRequested: root.handleEscape()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) { if (t === "r" || t === "R") root.refresh() }

      Flickable {
        anchors.fill: parent
        contentWidth: width; contentHeight: content.implicitHeight
        clip: true; boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: content
          width: parent.width
          spacing: Style.space(10)

          Item {
            width: parent.width
            implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, refreshButton.height)

            OpenVpnIconButton {
              id: backButton
              visible: root.settingsOpen
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              foreground: root.foreground; dim: root.dim; fontFamily: root.fontFamily
              icon: ""
              onActivated: root.closeSettings()
            }

            Text {
              id: heroIcon
              visible: !root.settingsOpen
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: root.vpnIcon
              color: root.iconColor
              opacity: root.connectedCount > 0 ? 1 : 0.5
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }

            Column {
              id: heroLabels
              anchors.left: root.settingsOpen ? backButton.right : heroIcon.right
              anchors.leftMargin: Style.space(14)
              anchors.right: root.settingsOpen ? importButton.left : refreshButton.left
              anchors.rightMargin: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                width: parent.width
                text: root.settingsOpen ? "Settings" : "OpenVPN"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
              }
              Text {
                width: parent.width
                text: (root.settingsOpen ? "OpenVPN" : root.heroStatus).toUpperCase()
                textFormat: Text.PlainText
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
                elide: Text.ElideRight
              }
            }

            OpenVpnIconButton {
              id: importButton
              visible: root.settingsOpen
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              foreground: root.foreground; dim: root.dim; fontFamily: root.fontFamily
              icon: "\uf067"
              busy: service.importRunning
              onActivated: root.openImportPicker()
            }

            OpenVpnIconButton {
              id: refreshButton
              visible: !root.settingsOpen
              anchors.right: settingsButton.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              foreground: root.foreground; dim: root.dim; fontFamily: root.fontFamily
              icon: "\uf021"
              onActivated: root.refresh()
            }

            OpenVpnIconButton {
              id: settingsButton
              visible: !root.settingsOpen
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              foreground: root.foreground; dim: root.dim; fontFamily: root.fontFamily
              icon: "\uf013"
              onActivated: root.openSettings()
            }
          }

          Rectangle { width: parent.width; height: 1; color: root.foreground; opacity: 0.14 }

          Text {
            visible: root.lastError !== ""; width: parent.width; text: root.lastError
            textFormat: Text.PlainText
            color: bar ? bar.urgent : Color.urgent; wrapMode: Text.Wrap
            font.family: root.fontFamily; font.pixelSize: Style.font.caption
          }

          OpenVpnReveal {
            shown: !root.settingsOpen
            width: parent.width

            // Counted by index, so rows survive each refresh and can animate their
            // own changes; the name sort keeps each index on the same profile.
            Repeater {
              model: root.profiles.length
              delegate: Column {
                id: row
                required property int index
                readonly property var profile: root.profiles[index]
                  || ({ uuid: "", name: "", active: false, connecting: false, disconnecting: false })
                readonly property var details: root.connectionDetails[profile.uuid] || ({})
                width: content.width

                Rectangle { visible: row.index > 0; width: parent.width; height: 1; color: root.foreground; opacity: 0.14 }

                RowLayout {
                  width: parent.width; height: Style.space(48); spacing: Style.space(10)
                  Text {
                    id: profileIconText
                    Layout.leftMargin: Style.space(8)
                    text: root.profileIcon
                    color: row.profile.active ? root.foreground : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.subtitle
                    opacity: root.busyUuid === row.profile.uuid ? 0.45 : 1
                  }
                  ColumnLayout {
                    Layout.fillWidth: true; spacing: 0
                    Text { Layout.fillWidth: true; text: row.profile.name; textFormat: Text.PlainText; color: root.foreground; elide: Text.ElideRight; font.family: root.fontFamily; font.pixelSize: Style.font.body }
                    Text {
                      text: service.profileStatus(row.profile)
                      textFormat: Text.PlainText
                      color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption
                    }
                  }
                  // Bound to the profile state and never set by hand, so a
                  // cancelled credential dialog leaves the switch off.
                  ToggleSwitch {
                    Layout.rightMargin: Style.space(8)
                    checked: service.profileSwitchOn(row.profile)
                    busy: root.busyUuid !== "" || row.profile.connecting || row.profile.disconnecting
                    // ToggleSwitch only ignores clicks while busy; dim it as well.
                    opacity: busy ? 0.55 : 1
                    Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    foreground: root.foreground
                    accent: Color.accent
                    onToggled: root.setConnection(row.profile)
                  }
                }

                OpenVpnReveal {
                  shown: row.profile.active
                  width: parent.width
                  Column {
                    x: Style.space(8) + profileIconText.width + Style.space(10)
                    width: parent.width - x - Style.space(8)
                    bottomPadding: Style.space(8)
                    spacing: Style.space(4)
                    OpenVpnInfoPair { foreground: root.foreground; dim: root.dim; fontFamily: root.fontFamily; label: "Interface"; value: row.details.device || "—" }
                    OpenVpnInfoPair { foreground: root.foreground; dim: root.dim; fontFamily: root.fontFamily; label: "Address"; value: row.details.address || "—" }
                    OpenVpnInfoPair { foreground: root.foreground; dim: root.dim; fontFamily: root.fontFamily; label: "Gateway"; value: row.details.gateway || "—" }
                    OpenVpnInfoPair { foreground: root.foreground; dim: root.dim; fontFamily: root.fontFamily; label: "DNS"; value: row.details.dns || "—" }
                  }
                }
              }
            }
          }

          OpenVpnReveal {
            shown: root.settingsOpen
            width: parent.width

            OpenVpnSettingsView {
              width: parent.width
              profiles: root.profiles
              busyUuid: root.busyUuid
              allowSeveralConnections: root.allowSeveralConnections
              foreground: root.foreground; dim: root.dim; fontFamily: root.fontFamily
              urgentColor: bar ? bar.urgent : Color.urgent
              profileIcon: root.profileIcon
              onSeveralConnectionsToggled: root.persistSettings({ allowSeveralConnections: !root.allowSeveralConnections })
              onRenameRequested: function(profile) { root.requestRename(profile) }
              onDeleteRequested: function(profile) { root.requestDelete(profile) }
            }
          }

        }
      }

      Rectangle {
        visible: root.authUuid !== ""
        anchors.fill: parent
        z: 10
        color: Qt.rgba(0, 0, 0, 0.62)
        opacity: visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

        // The dimmed area is part of the dialog: clicks on it must not reach
        // the switches and buttons underneath.
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; hoverEnabled: true }

        Rectangle {
          id: authCard
          anchors.centerIn: parent
          width: Math.min(parent.width - Style.space(24), Style.space(320))
          height: authColumn.implicitHeight + Style.space(28)
          radius: Style.space(6)
          color: Color.popups.background
          border.width: 1
          border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.22)

          Column {
            id: authColumn
            anchors.centerIn: parent
            width: parent.width - Style.space(28)
            spacing: Style.space(12)

            Text { width: parent.width; text: "Connect to " + root.authName; textFormat: Text.PlainText; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.title; font.bold: true; elide: Text.ElideRight }
            Text { width: parent.width; text: "Enter the credentials required by this OpenVPN profile. Certificate-only profiles need none \u2014 leave both blank and press Connect."; color: root.dim; wrapMode: Text.WordWrap; font.family: root.fontFamily; font.pixelSize: Style.font.caption }

            Text {
              visible: root.lastError !== ""
              width: parent.width
              text: root.lastError
              textFormat: Text.PlainText
              color: bar ? bar.urgent : Color.urgent
              wrapMode: Text.WordWrap
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            TextField {
              id: usernameField
              width: parent.width
              placeholderText: "Username"
              text: service.authUsername
              foreground: root.foreground
              accent: Color.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              onTextChanged: service.authUsername = text
              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) { root.cancelAuthentication(); event.accepted = true }
                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { passwordField.forceActiveFocus(); event.accepted = true }
              }
            }

            TextField {
              id: passwordField
              width: parent.width
              password: true
              placeholderText: "Password"
              text: service.authPassword
              foreground: root.foreground
              accent: Color.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              onTextChanged: service.authPassword = text
              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) { root.cancelAuthentication(); event.accepted = true }
                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.submitAuthentication(); event.accepted = true }
              }
            }

            Row {
              anchors.right: parent.right
              spacing: Style.space(8)
              OpenVpnSmallButton { foreground: root.foreground; dim: root.dim; fontFamily: root.fontFamily; urgentColor: bar ? bar.urgent : Color.urgent; label: "Cancel"; onActivated: root.cancelAuthentication() }
              OpenVpnSmallButton { foreground: root.foreground; dim: root.dim; fontFamily: root.fontFamily; urgentColor: bar ? bar.urgent : Color.urgent; label: service.authenticationRunning ? "Connecting…" : "Connect"; enabled: !service.authenticationRunning && ((service.authUsername.trim() !== "" && service.authPassword !== "") || (service.authUsername.trim() === "" && service.authPassword === "")); onActivated: root.submitAuthentication() }
            }
          }
        }
      }

      Rectangle {
        visible: root.renameUuid !== ""
        anchors.fill: parent
        z: 10
        color: Qt.rgba(0, 0, 0, 0.62)
        opacity: visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; hoverEnabled: true }

        Rectangle {
          id: renameCard
          anchors.centerIn: parent
          width: Math.min(parent.width - Style.space(24), Style.space(320))
          height: renameColumn.implicitHeight + Style.space(28)
          radius: Style.space(6)
          color: Color.popups.background
          border.width: 1
          border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.22)

          Column {
            id: renameColumn
            anchors.centerIn: parent
            width: parent.width - Style.space(28)
            spacing: Style.space(12)

            Text { width: parent.width; text: "Rename VPN profile"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.title; font.bold: true }
            Text { width: parent.width; text: "Choose a new display name for “" + root.renameOriginalName + "”."; textFormat: Text.PlainText; color: root.dim; wrapMode: Text.WordWrap; font.family: root.fontFamily; font.pixelSize: Style.font.caption }

            TextField {
              id: renameField
              width: parent.width
              placeholderText: "Profile name"
              text: root.renameName
              foreground: root.foreground
              accent: Color.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              onTextChanged: root.renameName = text
              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) { root.cancelRename(); event.accepted = true }
                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.confirmRename(); event.accepted = true }
              }
            }

            Row {
              anchors.right: parent.right
              spacing: Style.space(8)
              OpenVpnSmallButton { foreground: root.foreground; dim: root.dim; fontFamily: root.fontFamily; urgentColor: bar ? bar.urgent : Color.urgent; label: "Cancel"; onActivated: root.cancelRename() }
              OpenVpnSmallButton {
                foreground: root.foreground
                dim: root.dim
                fontFamily: root.fontFamily
                urgentColor: bar ? bar.urgent : Color.urgent
                label: "Rename"
                enabled: root.renameName.trim() !== "" && root.renameName.trim() !== root.renameOriginalName
                onActivated: root.confirmRename()
              }
            }
          }
        }
      }

      // Escape reaches PanelKeyCatcher (not blocked here), and handleEscape
      // cancels a pending delete first.
      Rectangle {
        visible: root.pendingDeleteUuid !== ""
        anchors.fill: parent
        z: 10
        color: Qt.rgba(0, 0, 0, 0.62)
        opacity: visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; hoverEnabled: true }

        Rectangle {
          id: deleteCard
          anchors.centerIn: parent
          width: Math.min(parent.width - Style.space(24), Style.space(320))
          height: deleteColumn.implicitHeight + Style.space(28)
          radius: Style.space(6)
          color: Color.popups.background
          border.width: 1
          border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.22)

          Column {
            id: deleteColumn
            anchors.centerIn: parent
            width: parent.width - Style.space(28)
            spacing: Style.space(12)

            Text { width: parent.width; text: "Delete VPN profile"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.title; font.bold: true }
            Text {
              width: parent.width
              text: "Delete “" + root.pendingDeleteName + "”?" + (root.pendingDeleteConnected ? " It will be disconnected first." : "")
              textFormat: Text.PlainText
              color: root.dim
              wrapMode: Text.Wrap
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Row {
              anchors.right: parent.right
              spacing: Style.space(8)
              OpenVpnSmallButton { foreground: root.foreground; dim: root.dim; fontFamily: root.fontFamily; urgentColor: bar ? bar.urgent : Color.urgent; label: "Cancel"; onActivated: root.cancelDelete() }
              OpenVpnSmallButton { foreground: root.foreground; dim: root.dim; fontFamily: root.fontFamily; urgentColor: bar ? bar.urgent : Color.urgent; label: "Delete"; urgent: true; enabled: !service.actionRunning; onActivated: root.confirmDelete() }
            }
          }
        }
      }
    }
  }

}
