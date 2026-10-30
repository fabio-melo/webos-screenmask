# What failed

This project went through three designs before the current one. They all
worked to some degree, and each had a cost that made it unacceptable. They are
recorded here so nobody has to try them again.

The goal never changed: a black strip at the bottom of the screen, above every
app, that survives reboots.

## 1. Replace the compositor root, restart the compositor

The first design copied the stock compositor root,
`WebOSCompositorBase/main.qml`, added the mask rectangle, and bind-mounted the
copy over the original. Compositor QML only loads at start, so a deferred
systemd unit restarted `surface-manager-daemon`.

Safeguards around the restart:

- The unit waited 60 s, then waited for the webosbrew failsafe flag to clear
  and for the power state `Active`. A restart inside `run-parts` risked a
  failsafe boot.
- Before mounting, it compared the MD5 of the stock `main.qml` with the one
  saved at install. A firmware update would otherwise load an old root over a
  new firmware.
- A watchdog waited 45 s for confirmation. Without it, the watchdog unmounted
  the copy, disabled the hook and restarted the compositor again.

**Why it failed:**

- Every boot blanked the screen and restarted the UI about a minute in.
- The watchdog read its confirmation from the rotating system logs. On one boot
  the mask logged its confirmation, the log rotated, and the watchdog missed
  it. Forty-three seconds later it restarted the compositor and disabled the
  hook. The saved state still said "on".

**What survived:** a confirmation that does not depend on logs. The mask writes
its own ACK file in tmpfs, with the revision it applied. Every later design
kept it.

## 2. `WEBOS_COMPOSITOR_MAIN`

The compositor binary contains a `WEBOS_COMPOSITOR_MAIN` variable, apparently
for choosing the QML root. On the C1 the Starfish plugin ignores it. Dropped
without further work.

## 3. Load the mask before the first frame

To avoid the restart, the next design tried to inject the mask before the
compositor drew its first frame. It added a marked block to the compositor's
systemd EnvironmentFile, `/var/systemd/system/env/surface-manager.env`, with a
preload bootstrap.

**Why it failed:** the C1 restores `surface-manager` from a boot snapshot, even
after a full reboot. The process that draws the first frame never reads the
environment. The bootstrap never ran early enough.

**What survived:** the fact itself. Nothing configurable runs before the first
root hook. The masks cannot cover the first seconds of boot, and the docs say
so.

## 4. Current: attach to the running compositor

`com.webos.service.systemUIManager/launch` loads QML into the compositor that
is already running. A hidden helper with no focus creates the mask on the
compositor root and stays alive to keep the mask's QML context. A supervisor
attaches again when the heartbeat stops.

No restart, no wait, no flicker. The mask appears at the first root hook. See
[how it works](how-it-works.md).

## 5. During validation: one `appId` for every build

The first version of this package launched every build under the same
`appId`. On the TV, an upgrade never loaded: the compositor answered
`returnValue:true` and kept the old helper.

The obvious fix was to close the old helper first. `closeByAppId` also
answered `returnValue:true`, and the helper stayed in the `closing` state for
good. Each later launch for that `appId` was refused and re-queued by the
compositor, about 55 times per second. Stopping the loader did not stop it.
Only a reboot did.

The fix: one `appId` per build, and never close a helper. The new helper
replaces the masks, and the old one stays idle until the next boot.

## Lessons

- Do not restart the compositor to load QML. Attach to the running one.
- Confirm effects with your own signal. Logs rotate, and webOS services return
  `returnValue:true` for calls with no effect. It happened twice in this
  project: launch and close.
- Test a recovery call before you depend on it. `closeByAppId` looked like the
  safe way to unload a helper and turned out to be the most dangerous call in
  the project.
- A safety net that can misfire needs the same scrutiny as the feature. The
  watchdog caused the worst failure of the first design.
- Measure when your code first runs. On the C1, snapshot restore defines that
  moment, not the boot order.
