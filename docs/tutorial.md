# Tutorial: mask a delaminated edge

This walks through masking real damage on an LG OLED: a delaminated strip
along the bottom edge. It takes about 10 minutes.

## Before you start: root and SSH

webos-screenmask runs on the TV as root and is installed over SSH. The TV
needs both before step 1.

1. **Root the TV.** Use [RootMyTV](https://rootmy.tv/), or follow the
   [Homebrew Channel](https://github.com/webosbrew/webos-homebrew-channel)
   instructions for your firmware. Either way, you end up with the Homebrew
   Channel app installed and running as root.
2. **Turn on the SSH server.** Open the Homebrew Channel, open its settings
   and turn on **SSH Server**. The SSH server is off by default, and nothing
   in this tutorial works without it. Reboot the TV if the app asks you to.
3. **Find the TV IP address.** On the TV, open **Settings → All Settings →
   General → Network**, then your wired or Wi-Fi connection. Note the IP
   address, for example `192.168.1.50`. A fixed address in your router helps:
   otherwise it can change.
4. **Test the connection** from your computer:

   ```sh
   ssh root@192.168.1.50
   ```

   The default password is `alpine`. The first connection asks you to trust
   the TV key: answer `yes`. A `~ #` prompt means it works. Type `exit` to
   leave.

   On Windows 10 and 11, `ssh` works in PowerShell or the Command Prompt. If it
   is missing, install **OpenSSH Client** in **Settings → Apps → Optional
   features**.

If the connection is refused, the SSH server is off: go back to step 2. If it
times out, check the IP address, and check that the computer and the TV are
on the same network.

Then install webos-screenmask. See the [README](../README.md#install). On
Windows, double-click `screenmask-windows.cmd` and choose **1 Install or
update**.

## 1. Find the damage

Delamination shows as dark, wavy areas along an edge. The pixels there stop
emitting light.

A screenshot does not show it. The TV captures the image it sends to the
panel, and that image is fine. The panel is what is damaged. Look at the
screen, or photograph it.

Show a bright, plain image to see the damage clearly, for example a white web
page in full screen. Note which edge is damaged and how far the dark waves
reach into the picture.

## 2. Add a red mask

Start with a mask larger than you think you need, and make it red so you can
see it against the damage:

```sh
screenmask add bottom 20          # prints the id, m1
screenmask set m1 color=#ff0000
screenmask on
```

`size` counts panel pixels. On a 4K panel the mask grows in steps of 2.

Red is the right color to place a mask. It is easy to photograph, and the
damage stands out against it. `screenmask preview` also paints the masks red,
but only for 15 seconds by default. A red `color` stays until you change it.

## 3. Read the result

![Red bottom mask over a delaminated edge](images/delamination-red-mask.jpg)

*The bottom-right corner of the screen, on a white page, with a 20 px red
mask on the bottom edge. The rings in the white area are camera moiré, not
damage.*

What the photo shows:

- **The red strip is the mask.** Its top edge is a straight line across the
  whole width.
- **The black waves inside the red are the delamination.** Those pixels do not
  light, so the red cannot show there. Toward the right corner, the damage
  fills the full height of the strip and no red is left.
- **Above the red line, the white is clean.** No black wave crosses the top
  edge of the mask. The damage is contained in the 20 px.

The rule: **every dark wave must stay below the straight top edge of the red
strip.** If a wave crosses that edge into the picture, the mask is too small.
Grow it and look again:

```sh
screenmask set m1 size=24
```

Where the damage reaches the top edge, as in the right corner of the photo,
the mask has no margin. Delamination can grow, so leave a few pixels of margin
there.

## 4. Cover only what you need

If only part of an edge is damaged, cover only that part. `start` and `length`
run along the edge: from the left for `top` and `bottom`, from the top for
`left` and `right`.

A thin mask along the whole edge, plus a thicker one on the worst part:

```sh
screenmask set m1 size=20
screenmask add bottom 28 2400 1440      # m2: from x=2400 to the right corner
screenmask set m2 color=#ff0000
```

Masks can overlap. Use as many as you need, on any edge.

## 5. Turn the masks black

When every dark wave sits inside the red, switch to black:

```sh
screenmask set m1 color=#000000
screenmask set m2 color=#000000
screenmask status
```

Look at the bright image again. The edge should now look like a straight black
border instead of a wavy one. On an OLED, black pixels are off, so the mask
adds no wear to the panel.

## 6. Check again later

Delamination can spread. Every few months, show a bright image, paint the
masks red for a minute, and confirm that the damage is still inside:

```sh
screenmask preview 60
```

## What the mask does not do

- It does not repair the panel. It hides the damaged area and gives up those
  pixels.
- It does not cover the first seconds of boot. The masks appear when the root
  hooks run: 39 s and 52 s after power-on in two measured boots.
- Screen Move (pixel shift) moves the picture by a few pixels. Whether the
  masks move with it is not verified yet. If you keep Screen Move on, leave
  some margin and check the edge after the TV has been on for a while.
