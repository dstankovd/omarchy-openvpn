import QtQuick
import QtTest
import ".."

TestCase {
  name: "OpenVpnServiceAuth"

  // queryHelper stays empty, so the service never starts a process.
  OpenVpnService { id: svc }

  readonly property var certProfile: ({ uuid: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", name: "Cert", active: false, connecting: false })
  readonly property var passwordProfile: ({ uuid: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb", name: "Password", active: false, connecting: false })

  function init() { svc.cancelAuthentication() }

  function test_certOnlyFollowsEachConnect() {
    // A failed certificate-only connect leaves authUuid set, so the next
    // Connect never passes through "": the flag must follow each Connect.
    verify(svc.setConnection(certProfile, true))
    compare(svc.authCertOnly, true)
    verify(svc.setConnection(passwordProfile, false))
    compare(svc.authUuid, passwordProfile.uuid)
    compare(svc.authCertOnly, false)
  }

  function test_cancelClearsCertOnly() {
    svc.setConnection(certProfile, true)
    svc.cancelAuthentication()
    compare(svc.authCertOnly, false)
  }
}
