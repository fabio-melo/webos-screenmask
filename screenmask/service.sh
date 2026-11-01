#!/bin/sh
# Start, stop or show the loader. Used by the boot hook, install.sh and
# uninstall.sh.
#
#   sh service.sh start | stop | status
#
# With systemd (webOS 6 and later, as far as tested), the loader runs as the
# screenmask unit in /run/systemd/system. Without systemd (older webOS), a
# small supervisor runs it in the background and restarts it when it exits.
PREFIX=${SCREENMASK_PREFIX:-@PREFIX@}
PIDFILE=${SCREENMASK_PIDFILE:-/tmp/screenmask-supervisor.pid}
UNIT_DIR=${SCREENMASK_UNIT_DIR:-/run/systemd/system}

# The usual check for a running systemd. SCREENMASK_SYSTEMD=yes|no forces it (tests).
has_systemd() {
    case ${SCREENMASK_SYSTEMD:-auto} in yes) return 0 ;; no) return 1 ;; esac
    command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]
}

supervisor_running() {
    [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null
}

case ${1:-} in
start)
    if has_systemd; then
        mkdir -p "$UNIT_DIR"
        cp "$PREFIX/screenmask.service" "$UNIT_DIR/screenmask.service" || exit 1
        systemctl daemon-reload || true
        systemctl start --no-block screenmask.service
        exit $?
    fi
    supervisor_running && exit 0
    # Detached from the caller: the boot hook must return at once, and an SSH
    # session must not take the supervisor down when it closes.
    if command -v setsid >/dev/null 2>&1; then
        setsid sh "$PREFIX/supervise.sh" </dev/null >/dev/null 2>&1 &
    else
        nohup sh "$PREFIX/supervise.sh" </dev/null >/dev/null 2>&1 &
    fi
    echo $! >"$PIDFILE"
    ;;
stop)
    if has_systemd; then
        systemctl stop screenmask.service 2>/dev/null
        rm -f "$UNIT_DIR/screenmask.service"
        systemctl daemon-reload 2>/dev/null
    fi
    if supervisor_running; then
        kill "$(cat "$PIDFILE")" 2>/dev/null
        i=0
        while supervisor_running && [ "$i" -lt 10 ]; do sleep 1; i=$((i + 1)); done
    fi
    rm -f "$PIDFILE"
    exit 0
    ;;
status)
    if has_systemd; then
        systemctl status screenmask.service --no-pager
    elif supervisor_running; then
        echo "supervisor running, pid $(cat "$PIDFILE")"
    else
        echo "supervisor not running"
        exit 3
    fi
    ;;
*)
    echo "usage: service.sh start | stop | status" >&2
    exit 2
    ;;
esac
