#!/bin/sh
# webos-screenmask boot hook, linked as /var/lib/webosbrew/init.d/01-screenmask.
#
# webosbrew runs init.d once per boot with run-parts. A hook that blocks breaks
# the boot, so this one only starts the loader unit and returns at once. /run is
# volatile, so the unit file is copied on every boot.
PREFIX=@PREFIX@
mkdir -p /run/systemd/system
cp "$PREFIX/screenmask.service" /run/systemd/system/screenmask.service || exit 0
systemctl daemon-reload || true
systemctl start --no-block screenmask.service || true
exit 0
