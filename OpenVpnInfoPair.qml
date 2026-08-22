import QtQuick
import qs.Commons

Row {
  required property color foreground
  required property color dim
  required property string fontFamily
  property string label: ""
  property string value: ""

  width: parent.width
  spacing: Style.space(8)

  Text { text: parent.label; color: parent.dim; font.family: parent.fontFamily; font.pixelSize: Style.font.bodySmall }
  Item { width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth - parent.spacing * 2); height: 1 }
  Text { text: parent.value; color: parent.foreground; font.family: parent.fontFamily; font.pixelSize: Style.font.bodySmall; elide: Text.ElideLeft; width: Math.min(implicitWidth, parent.width * 0.65) }
}
