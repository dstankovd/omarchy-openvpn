#!/bin/bash
# Tests for the bundled nmcli helpers. A fake nmcli on PATH records every call
# and answers as if one other VPN is already connected.

set -u

repo=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

mkdir "$work/bin"
cat > "$work/bin/nmcli" <<'FAKE'
#!/bin/bash
printf '%s\n' "$*" >> "$NMCLI_LOG"
case "$*" in
  "-g connection.type connection show uuid "*) echo vpn ;;
  "-g vpn.data connection show uuid "*) echo "connection-type = tls" ;;
  "--terse --fields UUID,TYPE connection show --active") echo "11111111-1111-1111-1111-111111111111:vpn" ;;
  "-g GENERAL.STATE connection show uuid "*) echo activated ;;
esac
exit 0
FAKE
chmod +x "$work/bin/nmcli"
# PATH holds only the fake and the tools the helpers need, so the real nmcli
# can never be reached and no test touches the system's connections.
for tool in bash timeout head tr sed sleep grep seq rm cat; do
  ln -s "$(command -v "$tool")" "$work/bin/$tool"
done
export PATH="$work/bin"
export NMCLI_LOG="$work/nmcli.log"

u1=aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa
u2=bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb
failed=0

check() {
  local name=$1; shift
  if "$@"; then echo "ok $name"; else echo "FAIL $name"; failed=1; fi
}

run() { : > "$NMCLI_LOG"; "$@" > "$work/out" 2>&1; }

connect_keeps_other_vpns_up() {
  printf '\n\n' | run "$repo/connect-profile" 22222222-2222-2222-2222-222222222222 || return 1
  ! grep -q "connection down" "$NMCLI_LOG"
}

details_with_two_uuids() {
  run "$repo/nmcli-query" details "$u1" "$u2" || return 1
  grep -q "connection show uuid $u1 uuid $u2\$" "$NMCLI_LOG"
}

rejected_without_nmcli() {
  run "$repo/nmcli-query" "$@"
  [[ $? -eq 2 && ! -s $NMCLI_LOG ]]
}

details_rejects_no_uuid() { rejected_without_nmcli details; }
details_rejects_bad_uuid() { rejected_without_nmcli details "$u1" not-a-uuid; }
details_rejects_33_uuids() {
  local many=()
  for _ in $(seq 33); do many+=("$u1"); done
  rejected_without_nmcli details "${many[@]}"
}

check "connect keeps other VPNs up" connect_keeps_other_vpns_up
check "details with two uuids" details_with_two_uuids
check "details rejects no uuid" details_rejects_no_uuid
check "details rejects bad uuid" details_rejects_bad_uuid
check "details rejects 33 uuids" details_rejects_33_uuids

if (( failed )); then exit 1; fi
echo "all helper tests passed"
