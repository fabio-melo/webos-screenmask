#!/bin/sh
# Install or upgrade webos-screenmask. Run as root on the TV, from the unpacked
# repository:
#
#   sh install.sh
#
# Idempotent. An upgrade keeps the existing masks.conf.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
PREFIX=${SCREENMASK_PREFIX:-/var/lib/screenmask}
INITD=${SCREENMASK_INITD:-/var/lib/webosbrew/init.d}
HOOK=$INITD/01-screenmask
BIN_DIR=${SCREENMASK_BIN_DIR:-/home/root/.local/bin}
ACK=/tmp/screenmask-ack.json
TESTED='Rockhopper release 6.4.0'

die() { echo "install: $*" >&2; exit 1; }
warn() { echo "install: warning: $*" >&2; }

# luna-send prints nothing without a terminal on stdin; tty-run gives it one.
luna() {
    sh "$HERE/screenmask/tty-run" luna-send -n 1 -w 3000 "$1" "$2" 2>/dev/null || true
}

detect_panel() {
    case $(luna luna://com.webos.service.tv.systemproperty/getSystemInfo '{"keys":["UHD"]}') in
        *'"UHD":"true"'*) echo 3840x2160 ;;
        *'"UHD":"false"'*) echo 1920x1080 ;;
        *)
            warn "could not detect the panel resolution; assuming 3840x2160. Change it with: screenmask panel <width>x<height>"
            echo 3840x2160
            ;;
    esac
}

# ---- preflight -------------------------------------------------------------
[ "$(id -u)" = 0 ] || die "run as root on the TV"
[ -d "$INITD" ] || die "$INITD not found. Root the TV first (RootMyTV or Homebrew Channel root)."
for tool in luna-send awk sed stat md5sum; do
    command -v "$tool" >/dev/null 2>&1 || die "required tool not found: $tool"
done
if ! command -v systemctl >/dev/null 2>&1; then
    warn "no systemd on this TV: the loader runs under a background supervisor instead (not validated on this webOS)"
fi
if ! command -v script >/dev/null 2>&1 && ! command -v python >/dev/null 2>&1 && ! command -v python3 >/dev/null 2>&1; then
    warn "neither script nor python found: luna-send runs without a terminal and may print nothing"
fi
[ -f "$HERE/screenmask/Masks.qml" ] || die "run this script from the unpacked repository"
release=$(cat /etc/starfish-release 2>/dev/null || echo unknown)
case $release in
    "$TESTED"*) ;;
    *) warn "tested only on '$TESTED' (LG C1). This TV reports '$release'. Continuing." ;;
esac
[ -d /usr/lib/qml/WebOSCompositorBase ] || warn "WebOSCompositorBase not found; the compositor layout may differ"

# ---- files -----------------------------------------------------------------
build=$(cat "$HERE"/screenmask/* | md5sum | cut -c1-12)
[ ! -f "$PREFIX/service.sh" ] || sh "$PREFIX/service.sh" stop
systemctl stop screenmask.service 2>/dev/null || true    # versions before service.sh
mkdir -p "$PREFIX"
for file in Attach.qml Masks.qml loader.sh boot-hook.sh screenmask.service screenmask \
    service.sh supervise.sh tty-run; do
    sed -e "s|@PREFIX@|$PREFIX|g" -e "s|@STATE_DIR@|$PREFIX|g" \
        -e "s|@ACK@|$ACK|g" -e "s|@BUILD@|$build|g" \
        "$HERE/screenmask/$file" >"$PREFIX/$file.new"
    mv "$PREFIX/$file.new" "$PREFIX/$file"
done
# /tmp is volatile: keep the uninstaller next to the files it removes.
cp "$HERE/uninstall.sh" "$PREFIX/uninstall.sh.new"
mv "$PREFIX/uninstall.sh.new" "$PREFIX/uninstall.sh"
chmod +x "$PREFIX/loader.sh" "$PREFIX/boot-hook.sh" "$PREFIX/screenmask" "$PREFIX/uninstall.sh" \
    "$PREFIX/service.sh" "$PREFIX/supervise.sh" "$PREFIX/tty-run"
echo "$build" >"$PREFIX/BUILD"

if [ ! -f "$PREFIX/masks.conf" ]; then
    revision=$(cat /proc/sys/kernel/random/uuid 2>/dev/null | tr -d '-' || true)
    cat >"$PREFIX/masks.conf.new" <<EOF
# webos-screenmask config. Change it with the screenmask command.
# mask <id> <edge> <size> <start> <length> <color>
#   edge: top | bottom | left | right. Sizes in panel pixels. length 0 = full edge.
enabled=0
revision=${revision:-$(date +%s)}
panel=$(detect_panel)
preview_until=0
EOF
    mv "$PREFIX/masks.conf.new" "$PREFIX/masks.conf"
fi

mkdir -p "$BIN_DIR"
ln -sf "$PREFIX/screenmask" "$BIN_DIR/screenmask"
ln -sf "$PREFIX/boot-hook.sh" "$HOOK"

# ---- start -----------------------------------------------------------------
# Same path as a real boot: the hook starts the loader unit.
sh "$HOOK"
i=0
while [ "$i" -lt 20 ]; do
    if grep -q '"build":"'"$build"'"' "$ACK" 2>/dev/null; then
        echo "install: attached (build $build)"
        "$PREFIX/screenmask" status
        exit 0
    fi
    sleep 1
    i=$((i + 1))
done
die "files installed, but the masks did not attach in 20s. Check: sh $PREFIX/service.sh status"
