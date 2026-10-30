# Foundations

The webOS behavior this feature depends on. Each item cost time to learn, and
most of them apply to any mod. Verified on an LG C1 with webOS 6.4.0.

## Root and boot hooks

RootMyTV and the Homebrew Channel run the scripts in
`/var/lib/webosbrew/init.d` with `run-parts`, as root, **once per boot**.
Waking from standby is not a boot: hooks do not run again.

A hook that does not return blocks `run-parts`. The next boot enters
**failsafe** mode, with the hooks disabled. Every hook must start its work
elsewhere and exit at once. This project's hook only starts a systemd unit.

A hook can be a symlink. Homebrew Channel apps use this to ship hooks inside
their app folder.

## Filesystem

| Path | Behavior |
|---|---|
| `/`, `/usr` | Read-only (squashfs). The compositor QML cannot be edited in place. |
| `/var`, `/home` | Persistent ext4. Code and config live here. |
| `/run`, `/tmp` | tmpfs. Cleared on every boot. |

Consequences for this project:

- The systemd unit lives in `/run`, so the boot hook copies it on every boot.
- The ACK lives in `/tmp`. A file written every second must not wear the flash,
  and a stale ACK must not survive a reboot.
- Temporary files go in the same folder as their target. A rename across
  filesystems (`/tmp` → `/var`) fails with `EXDEV` instead of being atomic.

## Long-running processes

The webOS SSH server kills every process of the session when the client
disconnects. `nohup`, `setsid` and `&` do not escape it. A long-running process
needs its own systemd unit, written to `/run/systemd/system` or started with
`systemd-run`.

Watch out for this shell pitfall:

```sh
systemd-run --unit=x cmd || setsid cmd &    # wrong: the whole list goes to the background
systemd-run --unit=x cmd || { setsid cmd & } # right: only the fallback does
```

Under SSH, the backgrounded list dies with the session before it runs. At boot
it survives by luck.

## luna-send

`luna-send` calls webOS services. Two traps:

1. It needs a terminal on stdin. With a pipe or `/dev/null` it runs, exits 0,
   and prints nothing. Scripts wrap it with `script -q -c '…' /dev/null`.
2. `"returnValue":true` means the service accepted the call. It does not mean
   the effect happened. Confirm the effect some other way. This project uses
   the ACK file.

## The compositor

`surface-manager` (unit `surface-manager-daemon`) is the Qt compositor. It
draws every app, input and menu. Its QML root is
`/usr/lib/qml/WebOSCompositorBase/main.qml`. `/usr/lib/qt5/qml` exposes the
same files.

Three facts shape this project:

1. **QML on disk does not reload.** A change to compositor QML takes effect
   only when `surface-manager-daemon` restarts. A restart blanks the screen and
   restarts the whole UI.
2. **The C1 restores the compositor from a boot snapshot,** even after a full
   reboot. Environment changes and preload libraries do not run before the
   first frame. Nothing configurable runs earlier than the first root hook.
3. **`com.webos.service.systemUIManager/launch` loads QML into the running
   compositor.** It needs no restart. This project is built on it.

## systemUIManager: launch and close

Two behaviors found while testing upgrades on the C1. Both answer
`"returnValue":true`.

1. **A launch for an `appId` that is already open does nothing.** The new QML
   never loads. To load new code, launch under a new `appId`. This project
   uses one `appId` per build.
2. **Never close a helper that never showed a window.** `closeByAppId` puts it
   in the `closing` state, and it stays there. From then on, every launch for
   that `appId` is refused and re-queued by the compositor, about 55 times per
   second, until the compositor restarts:

   ```
   LSM CLOSE_SYSTEMUI_BY_APPID {"appId":"…"}
   LSM VIEW_CONTAINER_STATE {"appId":"…","state":"closing"}
   surface-manager LSM dispatch, event is not accepted: type=launch, appId=…
   surface-manager LSM pushFrontPostEvent, pushFrontPostEvent
   ```

   Stopping the caller does not end the loop. Only a reboot or a compositor
   restart does.

## Getting files onto the TV

- The Homebrew Channel SSH server is dropbear **without `sftp-server`**. Recent
  OpenSSH clients run `scp` over SFTP, so `scp` fails. Send files through the
  SSH stdin (`tar … | ssh tv 'tar x…'`) or inside the command.
- dropbear drops a command longer than about **9000 characters**. The
  connection closes with `client_loop: send disconnect: Broken pipe`. A larger
  payload must go in parts.

## Seeing what is on screen

`com.webos.service.capture/executeOneShot` with `"method":"DISPLAY"` writes a
JPEG of the full output: video plus the UI layer, masks included.

```sh
luna-send -n 1 -w 8000 luna://com.webos.service.capture/executeOneShot \
  '{"path":"/tmp/shot.jpg","method":"DISPLAY","width":1920,"height":1080,"format":"JPEG"}'
```

This project's validation measured mask positions in such captures. A capture
does not show panel damage: it holds the image sent to the panel, not what
the panel emits.

## Finding what draws a window

The compositor logs every window that appears, with its app id and window
type:

```sh
tail -60 /var/log/messages | grep NL_VSC
```

```
LSM NL_VSC {"app_id":"com.webos.app.quickinputpicker","visible":true,
            "window_type":"_WEBOS_SYSTEM_UI_TYPE_OVERLAY"}
```

Start here before you guess which app or file draws a screen. The window type
tells you whether it is a system overlay, a card or a toast.
