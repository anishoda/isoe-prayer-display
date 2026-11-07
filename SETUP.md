# Setting up the ISOE prayer display on a TV

The display itself is already built and live:
**https://anishoda.github.io/isoe-prayer-display/**

This covers putting it on a wall so it runs unattended. Allow about two hours.

---

## First, check it

Open the link above on any phone or laptop. You should see today's five
prayer times with the next one highlighted, a live clock, and Jumu'ah.

- Add `?theme=light` for the light version. Dark is the default.
- The page changes shape by itself. Hold a phone upright and it rearranges
  into a tall board. Nothing to configure for that.

It is a single self-contained file. The whole year of prayer times is built
into the page, so once it has loaded it keeps working with no network at all.
That is deliberate: a prayer display that goes blank because the wifi dropped
during Fajr is worse than a printed sheet.

---

## Why a Pi and not the TV's own browser

After a power cut a smart TV comes back to its own home screen, not the
prayer times, and somebody has to find the remote. The Pi boots straight into
the display. For a screen people rely on for Fajr that is the whole argument.

---

## What you need

| Item | Cost | Notes |
| --- | --- | --- |
| 32 inch LED TV with HDMI | $70 to $250 | Avoid OLED, it burns in |
| Raspberry Pi 4 or 5 | — | Shatil has one |
| Official USB-C power supply | $12 | Underpowered supplies cause reboots |
| microSD card, 32GB | $10 | |
| **micro-HDMI to HDMI cable** | $8 | Pi 4 and 5 do not have full size HDMI. This catches everyone |
| VESA wall mount | $30 | Check the TV's hole pattern first |

---

## Step 1. Prepare the card

On a normal computer with the microSD card plugged in:

1. Install **Raspberry Pi Imager** from raspberrypi.com/software
2. Choose:
   - Device: your Pi model
   - OS: **Raspberry Pi OS (64-bit)**, the full Desktop version, not Lite
   - Storage: the microSD card
3. Click **Next**, then **Edit Settings**. Do not skip this.
4. General tab:
   - Hostname: `isoe-display`
   - Username and password: anything, write them down
   - Wireless LAN: the masjid wifi, country **US**
   - Locale time zone: **America/Los_Angeles**
5. Services tab: tick **Enable SSH**, password authentication
6. Write the card.

## Step 2. First boot

1. Card into the Pi.
2. Connect to the TV with micro-HDMI. **Use the HDMI port nearest the USB-C
   power connector** — that is HDMI0, the one that can control the TV later.
3. Power on, switch the TV to that input, wait for the desktop.
4. From your own machine:

```
ssh <username>@isoe-display.local
```

5. Turn on auto login so it comes up without anyone typing a password:

```
sudo raspi-config
```

**System Options** → **Boot / Auto Login** → **Desktop Autologin**. Finish,
and say **No** to rebooting yet.

## Step 3. Install

```
curl -fsSL https://raw.githubusercontent.com/anishoda/isoe-prayer-display/main/setup-pi.sh -o setup-pi.sh
chmod +x setup-pi.sh
sudo ./setup-pi.sh https://anishoda.github.io/isoe-prayer-display/
sudo reboot
```

For the light theme, quote the URL:

```
sudo ./setup-pi.sh "https://anishoda.github.io/isoe-prayer-display/?theme=light"
```

To hang the TV sideways, add rotation (`ROTATE=270` if it lands upside down):

```
sudo ROTATE=90 ./setup-pi.sh https://anishoda.github.io/isoe-prayer-display/
```

What the script sets up:

- Chromium full screen into the display on every boot
- A nightly job at 02:40 that fetches the latest prayer times
- HDMI-CEC jobs: TV on at 04:30, standby at 21:45
- Screen blanking and the mouse pointer off

The nightly fetch validates what it downloads before installing it, so a wifi
captive portal or an error page cannot replace working times with nonsense. A
failed fetch leaves yesterday's copy running.

## Step 4. TV settings

The TV still has its own ideas about sleeping and cropping:

- **HDMI CEC** (Anynet+, Bravia Sync, device control): **on**
- **Screen saver**: off
- **Sleep timer** / auto power off: off
- **Picture size**: nothing cropped at the edges. Some TVs overscan and would
  clip the top line.

## Step 5. The test that matters

```
systemctl status isoe-display-update.timer
/opt/isoe-display/update.sh
echo 'on 0' | cec-client -s -d 1
```

Then the real one: **pull the power on both, wait ten seconds, plug back in,
walk away, come back in three minutes.** It should be sitting on the prayer
display by itself. If not, it is not ready for a wall.

---

## If it goes sideways (literally)

Rotated, the display becomes a tall prayer board, one prayer per row. The page
handles the layout itself. But before drilling:

- **Test the viewing angle.** Budget LED panels look worse from above and
  below than from the sides. Rotate the TV and that weakness becomes the
  left-right direction, so colours wash out as you walk past. Stand it on its
  side on a table first and walk back and forth. You cannot tell from the spec
  sheet.
- **Most tilt mounts do not rotate.** Square VESA holes let you just bolt it
  on turned 90 degrees. Rectangular needs a rotating mount or adapter plate.

---

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| No picture | Wrong TV input, or cable in the wrong Pi socket. Use the port nearest USB-C power |
| Desktop instead of the display | Auto login off. Redo Step 2 item 5, reboot |
| Screen blanks after a while | `sudo raspi-config` → Display Options → Screen Blanking → off. Check the TV's screen saver too |
| TV will not wake itself | HDMI CEC off on the TV. Display still works, you just lose the schedule |
| Sideways the wrong way | Re-run with `ROTATE=270` instead of `90` |
| Times look wrong | Run `/opt/isoe-display/update.sh`. If isoeastvale.org/services is also wrong, the problem is upstream |
| Red "times need updating" screen | The annual calendar ran out. See below |

---

## Keeping it running

Nothing day to day. Iqamah times change a handful of times a year and the Pi
picks those up overnight by itself.

**One date for the calendar: October 31, 2027.** That is when the current
annual prayer calendar ends. After that the screen turns red and says the
times need updating rather than quietly showing something wrong.
