# How it works

## The short version

The masks are QML rectangles inside the running compositor, the process that
draws every app, input and menu. They sit above all of it. A native webOS
service loads them at runtime, so nothing restarts and nothing flickers.

```
boot
 └─ webosbrew run-parts
     └─ /var/lib/webosbrew/init.d/01-screenmask      (returns at once)
         └─ service.sh start                         (returns at once)
             └─ screenmask.service → loader.sh       (systemd unit, lives on)
                 └─ luna: systemUIManager/launch Attach.qml
                     └─ compositor (surface-manager)
                         └─ Attach.qml: hidden helper, no focus
                             └─ Masks.qml on the compositor root, above Views
                                 ├─ reads  /var/lib/screenmask/masks.conf  (every 1 s)
                                 └─ writes /tmp/screenmask-ack.json        (every 1 s)
```

### Without systemd

Older webOS versions have no systemd. There, `service.sh` starts
`supervise.sh` in the background instead of the unit. The supervisor runs
`loader.sh` and starts it again 5 s after it exits, like `Restart=on-failure`.
Its PID is in `/tmp/screenmask-supervisor.pid`. `setsid` detaches it from the
boot hook and from an SSH session.

This path passed on the C1 with systemd turned off by force. It has not run on
a TV without systemd yet.

## Files on the TV

| Path | Role |
|---|---|
| `/var/lib/screenmask/` | Code and config. Persistent. |
| `/var/lib/screenmask/masks.conf` | The masks. The only file you change, through `screenmask`. |
| `/var/lib/webosbrew/init.d/01-screenmask` | Symlink to `boot-hook.sh` |
| `/run/systemd/system/screenmask.service` | The loader unit, copied on every boot (systemd only) |
| `/tmp/screenmask-supervisor.pid` | The supervisor PID (no systemd only) |
| `/tmp/screenmask-ack.json` | Heartbeat written by the masks |
| `/home/root/.local/bin/screenmask` | Symlink to the CLI, on root's `PATH` |

## Attaching to the compositor

`loader.sh` calls `com.webos.service.systemUIManager/launch` with
`Attach.qml` as `main` and the window type `_WEBOS_SYSTEM_UI_TYPE_OVERLAY`. This
service loads system UI QML inside the compositor that is already running. It
does not start a process.

`Attach.qml` is a helper that never becomes visible:

1. It sets `needFocus: false` and `keepWindowOnAppSwitch: true` on its window.
   The foreground app keeps the focus and the remote keeps working.
2. It walks up from its window to the compositor root item.
3. It reads `Masks.qml` and creates it on the root with `Qt.createQmlObject`.
   The root is above Views, so the masks cover every app.
4. It destroys any previous masks first, by `objectName`. A second attach
   replaces the masks instead of stacking them.

The helper must stay alive. The masks' bindings and timer belong to its QML
context. This is why the helper is hidden instead of closed.

## Config and confirmation

`masks.conf` is plain text, so `sh` and `awk` can edit it and QML can read it:

```
enabled=1
revision=8f3a0c…
panel=3840x2160
preview_until=0
mask m1 bottom 20 0 0 #000000
mask m2 left 8 300 600 #000000
```

`Masks.qml` reads the file every second. It applies the masks when the
revision changes. An unreadable or invalid file keeps the last valid state. An
invalid mask line is skipped, not fatal.

After each read, the masks write the ACK:

```json
{"app":"org.fabs.screenmask","build":"3c9e1f2a7b10","revision":"8f3a0c…",
 "enabled":true,"masks":2,"previewing":false,"width":1920,"height":1080,
 "updatedAt":1792987675000}
```

The CLI uses it to confirm every change:

1. Copy the config, apply the change, and write a new `revision`.
2. Move the candidate over `masks.conf`. The move is atomic.
3. Wait up to 8 s for an ACK that carries the new revision.
4. Without it, restore the previous config and fail.

The config never claims a state that the screen did not confirm. A
`returnValue:true` from a webOS service is not proof that something happened.
The ACK is.

## Recovery and upgrades

`loader.sh` checks the ACK every 5 s. It attaches again when:

- the ACK is missing or older than 5 s: the masks are gone, for example after
  the system replaced the compositor
- the ACK `build` differs from `/var/lib/screenmask/BUILD`: an upgrade
  installed new QML

The build is a hash of the installed files. A healthy, current set of masks
costs nothing: the loader only reads a file.

Each build launches under its own `appId`, `org.fabs.screenmask.attach.<build>`.
The compositor ignores a launch for an `appId` that is already open, so a
shared `appId` would never load an upgrade. The new `Attach.qml` destroys the
previous masks by `objectName`. The previous helper is never closed: closing it
can jam the compositor (see [foundations](foundations.md#systemuimanager-launch-and-close)).
It stays idle and invisible until the next boot.

## Uninstall

`uninstall.sh` turns the masks off first, while they still read the config,
then removes the hook, the unit and the files. The hidden masks stay in
compositor memory until the next boot. Until then they keep writing
`/tmp/screenmask-ack.json`, so that file can reappear. It is harmless.

## Geometry

Masks use panel pixels. The compositor draws at its own resolution, 1920×1080
on the C1, and the panel scales it. The masks multiply by
`compositor height / panel height`:

- thickness rounds up, so a mask never covers less than you asked for
- start rounds down, for the same reason
- a mask never extends past the screen

`install.sh` detects the panel through
`com.webos.service.tv.systemproperty/getSystemInfo` (`UHD`). Override it with
`screenmask panel 3840x2160`.

`preview_until` holds an absolute time. The masks compare it with their own
clock, so a preview ends even if the command that started it dies.

## What it never does

- restart the compositor, the app manager or the TV
- take focus or change the foreground app
- change firmware partitions, TCON settings, Screen Move or the service menu

## Boot timing

The masks appear when webosbrew runs the first root hook. In validation that
was about 39 s of uptime. Frames before that point are not masked. The C1
restores the compositor from a boot snapshot, so no hook runs earlier. See
[foundations](foundations.md#the-compositor).
