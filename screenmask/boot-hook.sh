#!/bin/sh
# webos-screenmask boot hook, linked as /var/lib/webosbrew/init.d/01-screenmask.
#
# webosbrew runs init.d once per boot with run-parts. A hook that blocks breaks
# the boot, so this one only starts the loader in the background and returns
# at once.
sh @PREFIX@/service.sh start >/dev/null 2>&1 || true
exit 0
