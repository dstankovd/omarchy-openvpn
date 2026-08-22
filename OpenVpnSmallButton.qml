import QtQuick
import qs.Commons
import qs.Ui

Rectangle {
  id: button
  required property color foreground
  required property color dim
  required property string fontFamily
  property color urgentColor: Color.urgent
  property string label: ""
  property bool urgent: false
  signal activated()

  implicitWidth: labelItem.implicitWidth + Style.space(16)
  implicitHeight: Style.space(28)
  radius: Style.space(4)
  color: mouse.containsMouse && enabled ? Qt.rgba(foreground.r, foreground.g, foreground.b, 0.12) : "transparent"
  border.width: 1
  border.color: urgent ? urgentColor : dim
  opacity: enabled ? 1 : 0.5

  Text { id: labelItem; anchors.centerIn: parent; text: button.label; color: button.urgent ? button.urgentColor : button.foreground; font.family: button.fontFamily; font.pixelSize: Style.font.caption }
  MouseArea { id: mouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; enabled: button.enabled; onClicked: button.activated() }
}
