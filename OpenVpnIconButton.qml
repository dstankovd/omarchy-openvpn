import QtQuick
import qs.Commons

Rectangle {
  id: button
  required property color foreground
  required property color dim
  required property string fontFamily
  property string icon: ""
  property bool busy: false
  readonly property bool clickable: enabled && !busy
  signal activated()

  width: Style.space(34)
  height: Style.space(34)
  radius: Style.space(4)
  color: mouse.containsMouse && clickable ? Qt.rgba(foreground.r, foreground.g, foreground.b, 0.12) : "transparent"
  border.width: 1
  border.color: dim

  Text { anchors.centerIn: parent; text: button.icon; color: button.foreground; opacity: button.clickable ? 1 : 0.45; font.family: button.fontFamily; font.pixelSize: Style.font.caption }
  MouseArea { id: mouse; anchors.fill: parent; hoverEnabled: true; cursorShape: button.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor; enabled: button.clickable; onClicked: button.activated() }
}
