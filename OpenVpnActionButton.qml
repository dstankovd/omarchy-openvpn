import QtQuick
import qs.Commons

Rectangle {
  id: button
  required property color foreground
  required property color dim
  required property string fontFamily
  property string label: ""
  signal activated()

  height: Style.space(40)
  radius: Style.space(4)
  color: mouse.containsMouse ? Qt.rgba(foreground.r, foreground.g, foreground.b, 0.10) : "transparent"
  border.width: 1
  border.color: dim

  Text { anchors.centerIn: parent; text: button.label; color: button.foreground; font.family: button.fontFamily; font.pixelSize: Style.font.body }
  MouseArea { id: mouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: button.activated() }
}
