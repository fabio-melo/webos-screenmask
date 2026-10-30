#!/bin/sh
# Host-side tests for the loader and the CLI. External TV commands (luna-send,
# script) are stubs, and a background process plays the compositor: it writes
# the ACK the way Masks.qml does. Run with any POSIX shell:
#
#   sh tests/run.sh
#   TEST_SH="busybox sh" sh tests/run.sh    (closest to the TV shell)
#
# The QML parser and geometry run in node: tests/parse.test.js.
set -u
TEST_SH=${TEST_SH:-sh}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC=$ROOT/screenmask
PASS=0
FAIL=0
T=$(mktemp -d)
trap 'stop_compositor; rm -rf "$T"' EXIT

ok() { PASS=$((PASS + 1)); echo "ok   $1"; }
fail() { FAIL=$((FAIL + 1)); echo "FAIL $1"; [ $# -lt 2 ] || printf '     %s\n' "$2"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else fail "$1" "expected [$3], got [$2]"; fi; }
contains() { case $2 in *"$3"*) ok "$1" ;; *) fail "$1" "[$3] not in [$2]" ;; esac; }

# ---- fixtures --------------------------------------------------------------
STATE=$T/state
ACK=$T/ack.json
FAKEBIN=$T/bin
CALLS=$T/luna-calls
mkdir -p "$STATE" "$FAKEBIN"
cat >"$FAKEBIN/luna-send" <<EOF
#!/bin/sh
echo "\$*" >>"$CALLS"
EOF
# script -q -c <command> /dev/null
cat >"$FAKEBIN/script" <<'EOF'
#!/bin/sh
exec sh -c "$3"
EOF
chmod +x "$FAKEBIN/luna-send" "$FAKEBIN/script"
echo test >"$STATE/BUILD"

reset_conf() {
    cat >"$STATE/masks.conf" <<'EOF'
# test config
enabled=0
revision=r0
panel=3840x2160
preview_until=0
EOF
}

write_ack() { # <revision> <build>
    printf '{"app":"org.fabs.screenmask","build":"%s","revision":"%s","enabled":false,"masks":0,"previewing":false,"width":1920,"height":1080,"updatedAt":0}' \
        "$2" "$1" >"$ACK.tmp"
    mv "$ACK.tmp" "$ACK"
}

# start_compositor [freeze]: acknowledge every new revision, or keep the first one.
COMPOSITOR=
start_compositor() {
    frozen=$(sed -n 's/^revision=//p' "$STATE/masks.conf")
    (
        while :; do
            if [ "${1:-}" = freeze ]; then rev=$frozen; else rev=$(sed -n 's/^revision=//p' "$STATE/masks.conf"); fi
            write_ack "$rev" test
            sleep 0.2
        done
    ) &
    COMPOSITOR=$!
    sleep 0.3
}
stop_compositor() {
    [ -z "$COMPOSITOR" ] || { kill "$COMPOSITOR" 2>/dev/null; wait "$COMPOSITOR" 2>/dev/null; }
    COMPOSITOR=
    rm -f "$ACK"
}

cli() {
    SCREENMASK_STATE_DIR=$STATE SCREENMASK_ACK=$ACK SCREENMASK_ACK_TIMEOUT=${TIMEOUT:-3} \
        $TEST_SH "$SRC/screenmask" "$@"
}
masks() { grep '^mask ' "$STATE/masks.conf"; }

run_loader() {
    rm -f "$CALLS"
    PATH=$FAKEBIN:$PATH SCREENMASK_ONCE=1 SCREENMASK_PREFIX=$STATE SCREENMASK_ACK=$ACK $TEST_SH "$SRC/loader.sh"
    if [ -f "$CALLS" ]; then wc -l <"$CALLS" | tr -d ' '; else echo 0; fi
}

# ---- loader ----------------------------------------------------------------
rm -f "$ACK"
check "loader attaches when there is no ACK" "$(run_loader)" 1
contains "loader launches Attach.qml as a hidden overlay, appId per build" "$(cat "$CALLS")" \
    "systemUIManager/launch {\"appId\":\"org.fabs.screenmask.attach.test\",\"main\":\"file://$STATE/Attach.qml\",\"windowType\":\"_WEBOS_SYSTEM_UI_TYPE_OVERLAY\""

write_ack r0 test
check "loader does nothing while the ACK is fresh" "$(run_loader)" 0

write_ack r0 old-build
check "loader attaches again after an upgrade (build mismatch)" "$(run_loader)" 1

write_ack r0 test
touch -d "@$(( $(date +%s) - 60 ))" "$ACK"
check "loader attaches again when the heartbeat is stale" "$(run_loader)" 1

printf '{"app":"someone.else","build":"test"}' >"$ACK"
check "loader ignores an ACK from another app" "$(run_loader)" 1
rm -f "$ACK"

# ---- CLI: refusals without a compositor ------------------------------------
reset_conf
before=$(cat "$STATE/masks.conf")
cli on >/dev/null 2>&1
check "CLI refuses changes when the masks are not attached" "$?" 1
check "refused change leaves the config untouched" "$(cat "$STATE/masks.conf")" "$before"

for args in "add middle 20" "add bottom 0" "add bottom 1001" "add bottom 20 5" "add bottom x" "preview 0" "panel 4k"; do
    # shellcheck disable=SC2086
    cli $args >/dev/null 2>&1
    check "CLI rejects: $args" "$?" 1
done
check "rejected input leaves the config untouched" "$(cat "$STATE/masks.conf")" "$before"

# ---- CLI: changes confirmed by the compositor ------------------------------
reset_conf
start_compositor
check "add prints the new id" "$(cli add bottom 20)" m1
check "add stores defaults (start 0, full length, black)" "$(masks)" "mask m1 bottom 20 0 0 #000000"
check "second add gets the next id" "$(cli add left 8 300 600)" m2

cli set m1 size=24 start=100 length=800 color=#101010 >/dev/null
check "set changes several fields at once" "$(masks | head -n 1)" "mask m1 bottom 24 100 800 #101010"

cli set m1 size=0 >/dev/null 2>&1
check "set rejects an invalid size" "$?" 1
cli set m1 colour=#000000 >/dev/null 2>&1
check "set rejects an unknown key" "$?" 1
cli set m9 size=10 >/dev/null 2>&1
check "set rejects an unknown id" "$?" 1
check "rejected set leaves no candidate file behind" "$(ls "$STATE" | grep -c '\.new' || true)" 0

cli on >/dev/null
check "on sets enabled=1" "$(sed -n 's/^enabled=//p' "$STATE/masks.conf")" 1
cli off >/dev/null
check "off sets enabled=0" "$(sed -n 's/^enabled=//p' "$STATE/masks.conf")" 0

now=$(date +%s)
cli preview 30 >/dev/null
until=$(sed -n 's/^preview_until=//p' "$STATE/masks.conf")
if [ "$until" -ge $((now + 29)) ] && [ "$until" -le $((now + 32)) ]; then ok "preview stores an absolute end time"; else fail "preview stores an absolute end time" "$until"; fi

cli remove m2 >/dev/null
check "remove deletes only that mask" "$(masks | cut -d ' ' -f 2)" m1
check "add after remove takes the next id after the highest" "$(cli add top 10)" m2

cli panel 1920x1080 >/dev/null
check "panel override is stored" "$(sed -n 's/^panel=//p' "$STATE/masks.conf")" 1920x1080

status=$(cli status)
contains "status reports attached and applied" "$status" "attached: yes
applied:  yes"
contains "status lists the masks" "$status" "m1       bottom      24    100    800  #101010"
check "every change got a new revision" "$(grep -c '^revision=' "$STATE/masks.conf")" 1
stop_compositor

# ---- CLI: rollback when the compositor does not confirm --------------------
reset_conf
start_compositor freeze
before=$(cat "$STATE/masks.conf")
TIMEOUT=2 cli add bottom 20 >/dev/null 2>&1
check "unconfirmed change fails" "$?" 1
check "unconfirmed change restores the previous config" "$(cat "$STATE/masks.conf")" "$before"
check "rollback leaves no backup behind" "$(ls "$STATE" | grep -c '\.prev' || true)" 0
stop_compositor

# ---- QML parser and geometry -----------------------------------------------
if command -v node >/dev/null 2>&1; then
    if node --test "$ROOT/tests/parse.test.js" >"$T/node.log" 2>&1; then
        ok "QML parser and geometry ($(sed -n 's/^# pass //p' "$T/node.log") node tests)"
    else
        fail "QML parser and geometry" "$(cat "$T/node.log")"
    fi
else
    echo "skip QML parser and geometry (node not found)"
fi

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
