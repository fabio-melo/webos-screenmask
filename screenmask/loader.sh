#!/bin/sh
# webos-screenmask loader. Runs as the screenmask systemd unit.
#
# Attaches Attach.qml to the running compositor and attaches it again when the
# heartbeat stops, for example when the system replaces the compositor. It
# never restarts the compositor and never changes focus or the foreground app.
set -eu
PREFIX=${SCREENMASK_PREFIX:-@PREFIX@}
ACK=${SCREENMASK_ACK:-/tmp/screenmask-ack.json}
INTERVAL=${SCREENMASK_INTERVAL:-5}
MAX_AGE=5

# The masks are healthy when the ACK is fresh and comes from this build.
# A different build means an upgrade: attach again to load the new QML.
healthy() {
    [ -f "$ACK" ] || return 1
    age=$(( $(date +%s) - $(stat -c %Y "$ACK") ))
    [ "$age" -ge 0 ] && [ "$age" -le "$MAX_AGE" ] || return 1
    grep -q '"app":"org.fabs.screenmask"' "$ACK" &&
        grep -q '"build":"'"$(cat "$PREFIX/BUILD")"'"' "$ACK"
}

# Each build launches under its own appId. The compositor silently ignores a
# launch for an appId that is already open, so an upgrade with the same appId
# never loads. Never close the old helper either: closeByAppId on a helper that
# never showed a window leaves it "closing" forever, and the compositor then
# re-queues every launch for that appId about 55 times per second until it
# restarts. The new Attach.qml destroys the old masks; the old helper stays
# idle and invisible until the next boot.
attach() {
    app_id="org.fabs.screenmask.attach.$(cat "$PREFIX/BUILD")"
    payload='{"appId":"'"$app_id"'","main":"file://'"$PREFIX"'/Attach.qml","windowType":"_WEBOS_SYSTEM_UI_TYPE_OVERLAY","defaultWindowType":"overlay"}'
    # luna-send prints nothing without a terminal on stdin; script(1) gives it one.
    script -q -c "luna-send -n 1 -w 3000 luna://com.webos.service.systemUIManager/launch '$payload'" \
        /dev/null >/dev/null 2>&1 || true
}

while :; do
    healthy || attach
    [ "${SCREENMASK_ONCE:-0}" = 1 ] && exit 0
    sleep "$INTERVAL"
done
