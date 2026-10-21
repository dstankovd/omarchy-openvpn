import QtQuick
QtObject {
  property var command: []
  property bool running: false
  property bool stdinEnabled: false
  property QtObject stdout
  property QtObject stderr
  signal started()
  signal exited(int code)
  function write(data) {}
  function signal(sig) {}
}
