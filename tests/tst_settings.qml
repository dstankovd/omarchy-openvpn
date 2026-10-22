import QtQuick
import QtTest
import ".."

TestCase {
  name: "OpenVpnSettings"

  // queryHelper stays empty, so the service never starts a process.
  OpenVpnService { id: svc }

  readonly property string u: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"

  function init() { svc.allowSeveralConnections = true }

  function test_settingFlagFallsBack() {
    compare(svc.settingFlag(undefined, true), true)
    compare(svc.settingFlag(null, false), false)
    compare(svc.settingFlag("", true), true)
    compare(svc.settingFlag("maybe", false), false)
  }

  function test_settingFlagReadsBooleansAndStrings() {
    compare(svc.settingFlag(false, true), false)
    compare(svc.settingFlag(true, false), true)
    // omarchy bar set without --json stores the value as a string.
    compare(svc.settingFlag(" False ", true), false)
    compare(svc.settingFlag("true", false), true)
  }

  function test_connectCommandKeepsOthersByDefault() {
    compare(svc.connectCommand("/p/connect-profile", u), ["/p/connect-profile", u])
  }

  function test_connectCommandExclusiveWhenOff() {
    svc.allowSeveralConnections = false
    compare(svc.connectCommand("/p/connect-profile", u), ["/p/connect-profile", u, "--exclusive"])
  }
}
