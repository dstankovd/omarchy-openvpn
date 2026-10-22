#!/bin/bash
# Tests for the bundled nmcli helpers. A fake nmcli on PATH records every call
# and answers as if one other VPN is already connected. FAKE_STATE, FAKE_TYPE
# and FAKE_DOWN_FAIL change its answers for a single call.

set -u

repo=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

mkdir "$work/bin"
cat > "$work/bin/nmcli" <<'FAKE'
#!/bin/bash
printf '%s\n' "$*" >> "$NMCLI_LOG"
case "$*" in
  "-g connection.type connection show uuid "*) echo "${FAKE_TYPE-vpn}" ;;
  "-g vpn.data connection show uuid "*) echo "connection-type = tls" ;;
  "--terse --fields UUID,TYPE connection show --active") echo "11111111-1111-1111-1111-111111111111:vpn" ;;
  "-g GENERAL.STATE connection show uuid "*) echo "${FAKE_STATE-activated}" ;;
  "connection down uuid "*)
    if [[ -n ${FAKE_DOWN_FAIL:-} ]]; then echo "Error: down failed" >&2; exit 4; fi ;;
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

other=11111111-1111-1111-1111-111111111111
target=22222222-2222-2222-2222-222222222222

# Line number of the first log line matching a pattern.
line_of() {
  local hit
  hit=$(grep -n -m1 -- "$1" "$NMCLI_LOG") || return 1
  echo "${hit%%:*}"
}

# True when both patterns are logged and the first comes before the second.
logged_before() {
  local a b
  a=$(line_of "$1") && b=$(line_of "$2") && (( a < b ))
}

connect_exclusive_downs_other_vpns() {
  printf '\n\n' | run "$repo/connect-profile" "$target" --exclusive || return 1
  logged_before "connection down uuid $other" "connection up uuid $target"
}

connect_exclusive_keeps_its_own_profile() {
  printf '\n\n' | run "$repo/connect-profile" "$other" --exclusive || return 1
  ! grep -q "connection down" "$NMCLI_LOG"
}

connect_rejects_unknown_option() {
  run "$repo/connect-profile" "$target" --bogus </dev/null
  [[ $? -eq 2 && ! -s $NMCLI_LOG ]]
}

delete_disconnects_first() {
  FAKE_STATE=$1 run "$repo/delete-profile" "$u1" </dev/null || return 1
  logged_before "connection down uuid $u1" "connection delete uuid $u1"
}

delete_disconnects_active_first() { delete_disconnects_first activated; }
delete_disconnects_activating_first() { delete_disconnects_first activating; }

delete_inactive_skips_down() {
  FAKE_STATE= run "$repo/delete-profile" "$u1" </dev/null || return 1
  ! grep -q "connection down" "$NMCLI_LOG" && grep -q "connection delete uuid $u1" "$NMCLI_LOG"
}

delete_stops_when_down_fails() {
  FAKE_STATE=activated FAKE_DOWN_FAIL=1 run "$repo/delete-profile" "$u1" </dev/null
  [[ $? -ne 0 ]] && ! grep -q "connection delete" "$NMCLI_LOG" \
    && grep -q "Could not disconnect the profile" "$work/out"
}

delete_rejects_bad_uuid() {
  run "$repo/delete-profile" not-a-uuid </dev/null
  [[ $? -eq 2 && ! -s $NMCLI_LOG ]]
}

delete_rejects_non_vpn() {
  FAKE_TYPE=ethernet run "$repo/delete-profile" "$u1" </dev/null
  [[ $? -eq 2 ]] && ! grep -qE "connection (down|delete)" "$NMCLI_LOG"
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
check "connect exclusive downs other VPNs" connect_exclusive_downs_other_vpns
check "connect exclusive keeps its own profile" connect_exclusive_keeps_its_own_profile
check "connect rejects unknown option" connect_rejects_unknown_option
check "delete disconnects active first" delete_disconnects_active_first
check "delete disconnects activating first" delete_disconnects_activating_first
check "delete inactive skips down" delete_inactive_skips_down
check "delete stops when down fails" delete_stops_when_down_fails
check "delete rejects bad uuid" delete_rejects_bad_uuid
check "delete rejects non-VPN" delete_rejects_non_vpn

if (( failed )); then exit 1; fi
echo "all helper tests passed"
