#!/bin/sh
# Runs the loader and restarts it 5 s after it exits, like Restart=on-failure
# in the systemd unit. Used only on webOS without systemd.
PREFIX=${SCREENMASK_PREFIX:-@PREFIX@}
child=
trap '[ -z "$child" ] || kill "$child" 2>/dev/null; exit 0' TERM INT HUP
while :; do
    sh "$PREFIX/loader.sh" &
    child=$!
    wait "$child"
    child=
    sleep 5
done
