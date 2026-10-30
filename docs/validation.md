# Validation

## Test TV

LG OLED C1, webOS 6.4.0 (`Rockhopper release 6.4.0`), firmware 03.41.05,
rooted with RootMyTV. The compositor root is 1920×1080 on a 3840×2160 panel.

## Predecessor

The attach technique comes from an earlier, single-mask implementation. On the
same TV, that implementation passed these checks:

- Attach and toggle on/off kept the same compositor PID. No restart.
- HDMI1 kept focus and the remote kept working.
- The SystemUI foreground list stayed empty: the helper never became an app.
- The heartbeat continued after the attach.
- After a full reboot, the mask came back "on" at 38.8 s of uptime, at the
  first root hook, with the original compositor (`NRestarts=0`).
- The mask stayed after a switch to HDMI3.

## This package

Changes since the predecessor:

- several masks, any edge, segments, color per mask, red preview
- `Masks.qml` read at attach time instead of embedded in `Attach.qml`
- re-attach on build change after an upgrade
- CLI and installer on the TV, in `sh`

Host tests (`sh tests/run.sh`) cover the loader decisions, the CLI, the
rollback without confirmation, and the QML parser and geometry. They run under
`dash` and `busybox sh`.

On-TV results, 2026-10-30. Positions were measured in screen captures
(`capture/executeOneShot`, see [foundations](foundations.md#seeing-what-is-on-screen)),
in compositor pixels (1920×1080).

| Check | Result |
|---|---|
| Install attaches without a compositor restart | Pass. Same PID before and after, `NRestarts=0`. |
| Panel detection | Pass. `3840x2160` from `getSystemInfo` `UHD`. |
| Three masks on three edges, two of them segments | Pass. `bottom 20`, `left 8 300 600` and `top 6 0 1000` filled exactly rows 1070–1079, columns 0–3 × rows 150–449, and rows 0–2 × columns 0–499. Neighbor regions had 0% mask pixels. |
| `preview` shows red, then ends on its own | Pass. Red while active, gone after 30 s with no command. Works with masks off. |
| Change without confirmation restores the config | Pass. With a 0 s timeout: exit 1, config byte-identical (same MD5), no temporary files left. |
| Foreground app keeps focus | Pass. `getForegroundAppInfo` stayed `com.webos.app.hdmi1`. |
| Masks stay over the Home and after input switches | Pass for the Home and for HDMI2 → HDMI1. HDMI2 had no signal, so that capture was all black and proves nothing by itself. |
| Masks come back after a full reboot | Pass. Attached at 51.7 s of uptime, same compositor PID, `NRestarts=0`. |
| Upgrade replaces the masks without stacking | **Failed, then fixed.** See [what failed](what-failed.md#5-during-validation-one-appid-for-every-build). After the fix, the ACK carried only the new build (14 of 15 reads; the other read hit the file mid-write). |
| Uninstall hides the masks and removes every file | Pass. The masks left the screen, and no file, hook, link or unit was left. The ACK file reappears until reboot (expected). |
| Windows installer (`screenmask-windows.cmd`) | Pass. Run on Windows against the test TV. The TV side was also tested from Linux with the same commands: chunked transfer, unpack, line-ending cleanup, file checksums. |

## Limits

- Frames before the first root hook are not masked (about 39 s of boot).
- Sizes grow in steps of 2 panel pixels on a 4K panel.
- Masks follow the UI layer. Coverage under HDR, Dolby Vision, Screen Move
  (pixel shift) and the hardware cursor needs observation on the TV.
