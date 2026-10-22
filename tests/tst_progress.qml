import QtQuick
import QtTest
import ".."

TestCase {
  id: testCase
  name: "OpenVpnProgress"

  // A fresh service per test: the stub processes never stop running.
  Component { id: serviceComponent; OpenVpnService {} }

  readonly property string u: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"

  function make() { return createTemporaryObject(serviceComponent, testCase) }
  function profile(active) { return { uuid: u, name: "A", active: active, connecting: false, disconnecting: false } }

  function test_disconnectShowsDisconnecting() {
    var s = make()
    var p = profile(true)
    s.setConnection(p)
    compare(s.profileStatus(p), "Disconnecting…")
    compare(s.profileSwitchOn(p), false)
  }

  function test_connectShowsConnecting() {
    var s = make()
    var p = profile(false)
    verify(s.setConnection(p, true))
    s.submitAuthentication("/p/connect-profile")
    compare(s.profileStatus(p), "Connecting…")
    compare(s.profileSwitchOn(p), true)
  }

  function test_deleteShowsDeleting() {
    var s = make()
    var p = profile(true)
    s.deleteConnection(u, "/p/delete-profile")
    compare(s.profileStatus(p), "Deleting…")
  }

  function test_renameKeepsStatus() {
    var s = make()
    var p = profile(false)
    s.renameConnection(u, "B")
    compare(s.profileStatus(p), "Disconnected")
    compare(s.profileSwitchOn(p), false)
  }

  function test_networkManagerStates() {
    var s = make()
    var list = s.parseProfiles(u + ":A:vpn:wlp59s0:deactivating\nbbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb:B:vpn::activating")
    compare(list[0].disconnecting, true)
    compare(s.profileStatus(list[0]), "Disconnecting…")
    compare(s.profileStatus(list[1]), "Connecting…")
    compare(s.profileStatus(profile(true)), "Connected")
  }

  function test_busyStaysThroughStaleList() {
    // A list that started before the action ended still shows the old state.
    var s = make()
    s.queryHelper = "/p/nmcli-query"
    var p = profile(true)
    s.setConnection(p)
    s.refresh()
    s.settleAction()
    s.listOutput = u + ":A:vpn:wlp59s0:activated"
    s.listExitCode = 0
    s.listStreamFinished = true
    s.finalizeList()
    compare(s.busyUuid, u)
    compare(s.profileStatus(s.profiles[0]), "Disconnecting…")
  }

  function test_newActionCancelsSettling() {
    // A retry right after a failed connect starts while the old action settles.
    var s = make()
    s.queryHelper = "/p/nmcli-query"
    // (The stub processes never stop, so the first action runs on the
    // credential process and the second on the action process.)
    var other = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
    s.authUuid = u
    s.submitAuthentication("/p/connect-profile")
    s.settleAction()
    s.renameConnection(other, "B")
    s.refresh()
    s.listOutput = other + ":B:vpn::"
    s.listExitCode = 0
    s.listStreamFinished = true
    s.finalizeList()
    compare(s.busyUuid, other)
    compare(s.busyAction, "rename")
  }

  function test_actionErrorSurvivesList() {
    // A failed delete, disconnect or rename keeps its message after the
    // refresh that follows; the next action clears it.
    var s = make()
    s.queryHelper = "/p/nmcli-query"
    s.setError("Could not disconnect the profile, so it was not deleted.")
    s.refresh()
    s.listOutput = u + ":A:vpn::"
    s.listExitCode = 0
    s.listStreamFinished = true
    s.finalizeList()
    compare(s.lastError, "Could not disconnect the profile, so it was not deleted.")
  }

  function test_listErrorClearsOnSuccess() {
    var s = make()
    s.listOutput = "nmcli stalled"
    s.listExitCode = 1
    s.listStreamFinished = true
    s.finalizeList()
    compare(s.lastError, "nmcli stalled")
    s.listOutput = u + ":A:vpn::"
    s.listExitCode = 0
    s.finalizeList()
    compare(s.lastError, "")
  }

  function test_connectWaitsForRunningAction() {
    // A Connect submitted while another action runs must not start a second
    // process next to it.
    var s = make()
    s.renameConnection(u, "B")
    s.authUuid = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
    s.submitAuthentication("/p/connect-profile")
    compare(s.busyUuid, u)
    compare(s.busyAction, "rename")
  }

  function test_stuckBusyIsReleased() {
    // Busy with no process running and no refresh pending: a helper that
    // never started or never reported its exit.
    var s = make()
    s.startBusy(u, "delete")
    verify(s.releaseStuckBusy(Date.now()))
    compare(s.busyUuid, "")
    compare(s.busyAction, "")
  }

  function test_runningActionIsNotReleased() {
    var s = make()
    s.deleteConnection(u, "/p/delete-profile")
    verify(!s.releaseStuckBusy(Date.now() + 60000))
    compare(s.busyUuid, u)
  }

  function test_settlingIsReleasedOnlyWhenOld() {
    var s = make()
    s.startBusy(u, "disconnect")
    s.settleAction()
    verify(!s.releaseStuckBusy(Date.now()))
    compare(s.busyUuid, u)
    verify(s.releaseStuckBusy(Date.now() + s.busyWatchdogMs))
    compare(s.busyUuid, "")
  }

  function test_busyClearsAfterFreshList() {
    var s = make()
    s.queryHelper = "/p/nmcli-query"
    var p = profile(true)
    s.setConnection(p)
    s.settleAction()
    s.refresh()
    s.listOutput = u + ":A:vpn::"
    s.listExitCode = 0
    s.listStreamFinished = true
    s.finalizeList()
    compare(s.busyUuid, "")
    compare(s.busyAction, "")
    compare(s.profileStatus(s.profiles[0]), "Disconnected")
  }
}
