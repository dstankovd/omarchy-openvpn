import QtQuick

// Shows or hides its content by sliding its height and fading it, so the rows
// below glide instead of jumping. 140 ms OutCubic, as Omarchy's own panels.
Item {
  id: reveal
  property bool shown: true
  default property alias content: column.data

  implicitHeight: shown ? column.implicitHeight : 0
  height: implicitHeight
  opacity: shown ? 1 : 0
  // Hidden once fully folded, so a parent Column adds no spacing for it.
  visible: implicitHeight > 0 || opacity > 0
  clip: true

  Behavior on implicitHeight { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
  Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

  Column { id: column; width: parent.width }
}
