import QtQuick
import QtTest
import ".."

TestCase {
  name: "OpenVpnService"

  // queryHelper stays empty, so the service never starts a process.
  OpenVpnService { id: svc }

  readonly property string homeUuid: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
  readonly property string devUuid: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"

  function block(uuid, name, address, gateway, dns) {
    var lines = [
      "GENERAL.UUID:" + uuid,
      "GENERAL.NAME:" + name,
      "GENERAL.STATE:activated",
      "GENERAL.DEVICES:wlp59s0",
      "IP4.ADDRESS[1]:" + address,
      "IP4.GATEWAY:" + gateway
    ]
    if (dns !== "") lines.push("IP4.DNS[1]:" + dns)
    return lines.join("\n")
  }

  function init() {
    svc.connectionDetails = ({})
    svc.profiles = []
  }

  function test_parseDetailsTwoBlocks() {
    var r = svc.parseDetails(block(homeUuid, "Home", "10.8.0.2/24", "10.8.0.1", "10.8.0.1")
      + "\n\n" + block(devUuid, "HRM_DEV", "172.31.4.18/20", "172.31.0.1", "172.31.0.2"))
    compare(Object.keys(r).length, 2)
    compare(r[homeUuid].address, "10.8.0.2/24")
    compare(r[homeUuid].device, "wlp59s0")
    compare(r[homeUuid].state, "activated")
    compare(r[devUuid].gateway, "172.31.0.1")
    compare(r[devUuid].dns, "172.31.0.2")
  }

  function test_parseDetailsMissingFields() {
    var r = svc.parseDetails(block(homeUuid, "Home", "10.8.0.2/24", "", ""))
    compare(r[homeUuid].gateway, "")
    compare(r[homeUuid].dns, "")
  }

  function test_parseDetailsEscapedName() {
    var r = svc.parseDetails(block(homeUuid, "a\\:b", "10.8.0.2/24", "10.8.0.1", "10.8.0.1"))
    compare(Object.keys(r).length, 1)
    compare(r[homeUuid].address, "10.8.0.2/24")
  }

  function test_activeUuids() {
    svc.profiles = [
      { uuid: homeUuid, name: "Home", active: true },
      { uuid: "cccccccc-cccc-cccc-cccc-cccccccccccc", name: "HRM_PROD", active: false },
      { uuid: devUuid, name: "HRM_DEV", active: true }
    ]
    compare(svc.activeUuids(), [homeUuid, devUuid])
  }

  function test_profilesKeepNameOrderWhenConnected() {
    var p = svc.parseProfiles([
      "u1:Alpha:vpn::",
      "u2:Bravo:vpn:wlp59s0:activated",
      "u3:Charlie:vpn::"
    ].join("\n"))
    compare(p.map(function(x) { return x.name }), ["Alpha", "Bravo", "Charlie"])
  }

  function test_failedDetailsKeepPrevious() {
    svc.connectionDetails = { "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa": { state: "activated", device: "wlp59s0", address: "10.8.0.2/24", gateway: "10.8.0.1", dns: "10.8.0.1" } }
    svc.detailsOutput = "Error: bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb - no such connection profile."
    svc.detailsExitCode = 10
    svc.detailsStreamFinished = true
    svc.finalizeDetails()
    compare(svc.connectionDetails[homeUuid].address, "10.8.0.2/24")
  }
}
