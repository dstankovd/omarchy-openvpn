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
  readonly property var connectionInfo: service.connectionInfo
  readonly property bool nmcliAvailable: service.nmcliAvailable

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string configuredName: String(settings.connection || "").trim()
  readonly property int connectedCount: {
    var count = 0
    for (var i = 0; i < profiles.length; i++) if (profiles[i].active) count++
    return count
  }
  readonly property string activeProfileName: {
    for (var i = 0; i < profiles.length; i++) if (profiles[i].active) return profiles[i].name
    return ""
  }
  readonly property string connectingProfileName: {
    for (var i = 0; i < profiles.length; i++) if (profiles[i].connecting) return profiles[i].name
    return ""
  }
  readonly property color iconColor: connectedCount > 0 ? foreground : dim
  readonly property string vpnIcon: "󰖂"
  readonly property string profileIcon: "󰌆"
  readonly property string heroStatus: !nmcliAvailable ? "NetworkManager unavailable"
    : connectedCount > 0 ? "Connected" + (activeProfileName !== "" ? " · " + activeProfileName : "")
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
    if (service.setConnection(profile, bundledPath("connect-profile"))) {
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
  }

  function confirmDelete() {
    if (pendingDeleteUuid === "" || service.actionRunning) return
    service.deleteConnection(pendingDeleteUuid)
    cancelDelete()
  }

  function openImportPicker() {
    service.importProfile(bundledPath("import-profile"))
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  onOpenedChanged: if (opened) { refresh(); Qt.callLater(function() { keys.forceActiveFocus() }) }

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
    configuredName: root.configuredName
    refreshInterval: root.refreshInterval
    queryHelper: root.bundledPath("nmcli-query")
    onAuthenticationFailed: Qt.callLater(function() { passwordField.forceActiveFocus() })
    onAuthenticationPrompted: Qt.callLater(function() { usernameField.forceActiveFocus() })
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

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keys
    contentWidth: panel.fittedContentWidth(Style.space(430))
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(520))

    PanelKeyCatcher {
      id: keys
      anchors.fill: parent
      blocked: root.authUuid !== "" || root.renameUuid !== ""
      onCloseRequested: root.close()
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

            Text {
              id: heroIcon
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
              anchors.left: heroIcon.right
              anchors.leftMargin: Style.space(14)
              anchors.right: refreshButton.left
              anchors.rightMargin: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                width: parent.width
                text: "OpenVPN"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
              }
              Text {
                width: parent.width
                text: root.heroStatus.toUpperCase()
                textFormat: Text.PlainText
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
                elide: Text.ElideRight
              }
            }

            Rectangle {
              id: refreshButton
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(34)
              height: Style.space(34)
              radius: Style.space(4)
              color: refreshMouse.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12) : "transparent"
              border.width: 1
              border.color: root.dim
              Text { anchors.centerIn: parent; text: "\uf021"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
              MouseArea { id: refreshMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.refresh() }
            }
          }

          Rectangle { width: parent.width; height: 1; color: root.foreground; opacity: 0.14 }

          Text {
            visible: root.lastError !== ""; width: parent.width; text: root.lastError
            textFormat: Text.PlainText
            color: bar ? bar.urgent : Color.urgent; wrapMode: Text.Wrap
            font.family: root.fontFamily; font.pixelSize: Style.font.caption
          }

          Rectangle {
            visible: root.pendingDeleteUuid !== ""
            width: parent.width
            height: deleteColumn.implicitHeight + Style.space(18)
            radius: Style.space(4)
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
            border.width: 1
            border.color: bar ? bar.urgent : Color.urgent
            Column {
              id: deleteColumn
              anchors.centerIn: parent
              width: parent.width - Style.space(20)
              spacing: Style.space(8)
              Text {
                width: parent.width
                text: "Delete “" + root.pendingDeleteName + "”?"
                textFormat: Text.PlainText
                color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body
                elide: Text.ElideRight
              }
              Row {
                anchors.right: parent.right; spacing: Style.space(16)
                Text {
                  text: "Cancel"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.body
                  MouseArea { anchors.fill: parent; anchors.margins: -Style.space(5); cursorShape: Qt.PointingHandCursor; onClicked: root.cancelDelete() }
                }
                Text {
                  text: "Delete"; color: bar ? bar.urgent : Color.urgent; font.family: root.fontFamily; font.pixelSize: Style.font.body; font.bold: true
                  MouseArea { anchors.fill: parent; anchors.margins: -Style.space(5); cursorShape: Qt.PointingHandCursor; onClicked: root.confirmDelete() }
                }
              }
            }
          }

          Column {
            visible: root.connectedCount > 0
            width: parent.width
            spacing: Style.space(5)
            Text { text: "CONNECTION STATUS"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; font.letterSpacing: 1.1 }
            OpenVpnInfoPair { foreground: root.foreground; dim: root.dim; fontFamily: root.fontFamily; label: "Profile"; value: root.connectionInfo["GENERAL.NAME"] || "—" }
            OpenVpnInfoPair { foreground: root.foreground; dim: root.dim; fontFamily: root.fontFamily; label: "State"; value: root.connectionInfo["GENERAL.STATE"] || "Connected" }
            OpenVpnInfoPair { foreground: root.foreground; dim: root.dim; fontFamily: root.fontFamily; label: "Interface"; value: root.connectionInfo["GENERAL.DEVICES"] || "—" }
            OpenVpnInfoPair { foreground: root.foreground; dim: root.dim; fontFamily: root.fontFamily; label: "Address"; value: root.connectionInfo["IP4.ADDRESS[1]"] || root.connectionInfo["IP4.ADDRESS"] || "—" }
            OpenVpnInfoPair { foreground: root.foreground; dim: root.dim; fontFamily: root.fontFamily; label: "Gateway"; value: root.connectionInfo["IP4.GATEWAY"] || "—" }
            OpenVpnInfoPair { foreground: root.foreground; dim: root.dim; fontFamily: root.fontFamily; label: "DNS"; value: root.connectionInfo["IP4.DNS[1]"] || root.connectionInfo["IP4.DNS"] || "—" }
            Rectangle { width: parent.width; height: 1; color: root.foreground; opacity: 0.14 }
          }

          Repeater {
            model: root.profiles
            delegate: Rectangle {
              required property var modelData
              readonly property var profile: modelData
              width: content.width; height: Style.space(48); radius: Style.space(4)
              color: "transparent"
              RowLayout {
                anchors.fill: parent; anchors.leftMargin: Style.space(8); anchors.rightMargin: Style.space(8); spacing: Style.space(10)
                Text {
                  text: root.profileIcon
                  color: profile.active ? root.foreground : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.subtitle
                  opacity: root.busyUuid === profile.uuid ? 0.45 : 1
                }
                ColumnLayout {
                  Layout.fillWidth: true; spacing: 0
                  Text { Layout.fillWidth: true; text: profile.name; textFormat: Text.PlainText; color: root.foreground; elide: Text.ElideRight; font.family: root.fontFamily; font.pixelSize: Style.font.body }
                  Text {
                    text: profile.active ? "Connected" + (profile.device ? " · " + profile.device : "")
                      : profile.connecting ? "Connecting…" : "Disconnected"
                    textFormat: Text.PlainText
                    color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption
                  }
                }
                OpenVpnSmallButton { foreground: root.foreground; dim: root.dim; fontFamily: root.fontFamily; urgentColor: bar ? bar.urgent : Color.urgent; label: profile.active ? "Disconnect" : (profile.connecting ? "Connecting…" : "Connect"); enabled: root.busyUuid === "" && !profile.connecting; onActivated: root.setConnection(profile) }
                OpenVpnSmallButton { foreground: root.foreground; dim: root.dim; fontFamily: root.fontFamily; urgentColor: bar ? bar.urgent : Color.urgent; label: "Rename"; enabled: root.busyUuid === "" && !profile.connecting; onActivated: root.requestRename(profile) }
                OpenVpnSmallButton { foreground: root.foreground; dim: root.dim; fontFamily: root.fontFamily; urgentColor: bar ? bar.urgent : Color.urgent; label: "Delete"; urgent: true; enabled: root.busyUuid === "" && !profile.connecting; onActivated: root.requestDelete(profile) }
              }
            }
          }

          OpenVpnActionButton { width: parent.width; foreground: root.foreground; dim: root.dim; fontFamily: root.fontFamily; label: service.importRunning ? "Choose a profile…" : "Import profile"; enabled: !service.importRunning; onActivated: root.openImportPicker() }
        }
      }

      Rectangle {
        visible: root.authUuid !== ""
        anchors.fill: parent
        z: 10
        color: Qt.rgba(0, 0, 0, 0.62)

        Rectangle {
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

        Rectangle {
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
    }
  }

}
