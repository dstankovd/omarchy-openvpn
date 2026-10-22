import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// Settings view content: the several-connections option and the profile list
// with Rename and Delete. The panel header and dialogs stay in BarWidget.qml.
Column {
  id: view
  required property var profiles
  required property string busyUuid
  required property bool allowSeveralConnections
  required property color foreground
  required property color dim
  required property color urgentColor
  required property string fontFamily
  required property string profileIcon

  signal severalConnectionsToggled()
  signal renameRequested(var profile)
  signal deleteRequested(var profile)

  spacing: Style.space(10)

  Toggle {
    width: parent.width
    label: "Allow several connections"
    description: "When off, connecting a VPN disconnects the others first."
    checked: view.allowSeveralConnections
    foreground: view.foreground
    fontFamily: view.fontFamily
    onClicked: view.severalConnectionsToggled()
  }

  PanelSectionHeader {
    text: "PROFILES"
    foreground: view.foreground
    fontFamily: view.fontFamily
  }

  Text {
    visible: view.profiles.length === 0
    width: parent.width
    text: "No VPN profiles yet. Select + to import one."
    color: view.dim
    wrapMode: Text.WordWrap
    font.family: view.fontFamily
    font.pixelSize: Style.font.caption
  }

  Column {
    width: parent.width

    Repeater {
      model: view.profiles
      delegate: Column {
        id: row
        required property var modelData
        required property int index
        readonly property var profile: modelData
        width: parent.width

        Rectangle { visible: row.index > 0; width: parent.width; height: 1; color: view.foreground; opacity: 0.14 }

        RowLayout {
          width: parent.width; height: Style.space(48); spacing: Style.space(10)
          Text {
            Layout.leftMargin: Style.space(8)
            text: view.profileIcon
            color: row.profile.active ? view.foreground : view.dim
            font.family: view.fontFamily
            font.pixelSize: Style.font.subtitle
            opacity: view.busyUuid === row.profile.uuid ? 0.45 : 1
          }
          Text { Layout.fillWidth: true; text: row.profile.name; textFormat: Text.PlainText; color: view.foreground; elide: Text.ElideRight; font.family: view.fontFamily; font.pixelSize: Style.font.body }
          OpenVpnSmallButton { foreground: view.foreground; dim: view.dim; fontFamily: view.fontFamily; urgentColor: view.urgentColor; label: "Rename"; enabled: view.busyUuid === "" && !row.profile.connecting; onActivated: view.renameRequested(row.profile) }
          // A connected or connecting profile can be deleted: the helper
          // disconnects it first. Only the panel's own running action blocks it.
          OpenVpnSmallButton { Layout.rightMargin: Style.space(8); foreground: view.foreground; dim: view.dim; fontFamily: view.fontFamily; urgentColor: view.urgentColor; label: "Delete"; urgent: true; enabled: view.busyUuid === ""; onActivated: view.deleteRequested(row.profile) }
        }
      }
    }
  }
}
