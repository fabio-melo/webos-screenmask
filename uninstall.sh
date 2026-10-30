#!/bin/sh
# Remove webos-screenmask. Run as root on the TV:
#
#   sh /var/lib/screenmask/uninstall.sh
#
# The masks are hidden first, while the compositor still reads the config. Their
# invisible QML objects stay in compositor memory until it restarts (next boot).
set -u
PREFIX=${SCREENMASK_PREFIX:-/var/lib/screenmask}
INITD=${SCREENMASK_INITD:-/var/lib/webosbrew/init.d}
BIN_DIR=${SCREENMASK_BIN_DIR:-/home/root/.local/bin}

[ "$(id -u)" = 0 ] || { echo "uninstall: run as root on the TV" >&2; exit 1; }

if [ -x "$PREFIX/screenmask" ]; then
    "$PREFIX/screenmask" off || echo "uninstall: could not confirm 'off'; continuing" >&2
fi
systemctl stop screenmask.service 2>/dev/null || true
rm -f /run/systemd/system/screenmask.service
systemctl daemon-reload 2>/dev/null || true
rm -f "$INITD/01-screenmask" "$BIN_DIR/screenmask" /tmp/screenmask-ack.json
rm -rf "$PREFIX"
echo "uninstall: removed. Reboot to drop the hidden masks from compositor memory."
