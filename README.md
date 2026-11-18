# ISOE prayer display

Full-screen prayer times board for the Islamic Society of Eastvale musallah, and a complete guide to running it on a TV with a Raspberry Pi 4.

**Live:** https://anishoda.github.io/isoe-prayer-display/

A Raspberry Pi 4 boots straight into the page full screen, with no keyboard or remote needed. The page is a single self-contained file, so it keeps working if the wifi drops: the whole annual prayer calendar is built into it. That is deliberate, because a prayer display that goes blank during Fajr is worse than a printed sheet.

The Pi also switches the TV off and on over HDMI-CEC to follow the prayer timetable inside the page. The TV turns on 30 minutes before Fajr adhan and off 60 minutes after Isha iqamah. The times change through the year, so a fixed schedule would be wrong for months at a time.

| URL | Result |
| --- | --- |
| `/` | dark theme |
| `/?theme=light` | light theme |

The page detects portrait by itself, so a TV hung sideways needs no setting in the page. You only rotate the screen output (Step 5).

Allow about two hours per TV.

## Before you start

- Decide the orientation. Horizontal needs no rotation setting. For a vertical TV you need to know which way the top of the picture goes: `90` puts the top to the left, `270` puts it to the right. Test this on the TV before you mount it (Step 6).
- Have the TV on a table where you can reach its remote and HDMI ports. Mount it only after the tests pass.

## What you need

| Item | Notes |
| --- | --- |
| Raspberry Pi 4 | One per TV. |
| Official USB-C power supply (5V 3A) | Underpowered supplies cause reboots. |
| microSD card, 32 GB | Reputable brand, A1 or A2 rated. Cheap or old cards fail in ways that look like software problems. |
| Micro-HDMI to HDMI cable | Micro HDMI (Type D), not mini. A cable is better than an adapter on a wall mount because an adapter strains the Pi's small port. Any basic cable works for 1080p. |
| TV with HDMI-CEC | Avoid OLED because it burns in. Check that CEC is switched on in the TV menu. |
| Power cord for the TV | The older Vizio E-series use a 6 ft polarized figure-8 (C7P) cord with one squared and one rounded side. The VQD55R-1004 has an attached cord. |
| VESA wall mount | Check the hole pattern. Most tilt mounts do not rotate, so for a vertical TV you need square VESA holes or a mount that rotates. |
| A computer, and a card reader | To write the card with Raspberry Pi Imager. |

## Step 1. Write the card

On your computer with the card inserted:

- Install Raspberry Pi Imager from raspberrypi.com/software.
- Device: Raspberry Pi 4. OS: Raspberry Pi OS (64-bit), the full Desktop version, not Lite. Storage: the microSD card.
- Open the customisation screens. Do not skip them. Set a hostname (for example `isoe-display-2`), a username and password you will write down, the masjid wifi with country US, and time zone `America/Los_Angeles`. Turn on SSH with password login. Turn on Raspberry Pi Connect if you want remote access from a browser.
- Write the card.

If Imager says "Access denied" or shows the card as read-only, try in this order: run Imager as administrator; check the lock switch on the SD adapter; try another adapter or USB port; try another card. A worn card and a faulty adapter both cause this, so it is worth testing both.

## Step 2. First boot

- Put the card in the Pi and connect the TV with the micro-HDMI cable.
- Use the HDMI port nearest the USB-C power connector (HDMI0). That is the port that can control the TV.
- Connect power, switch the TV to that HDMI input, and wait for the desktop.
- Open a terminal on the Pi, or connect with Raspberry Pi Connect or SSH (`ssh username@hostname.local`).

## Step 3. Update the system

```
sudo apt update
sudo apt full-upgrade -y
sudo reboot
```

Repeat after the reboot until nothing is left to upgrade. Then check the Pi 4 bootloader firmware with `sudo rpi-eeprom-update`, and apply it with `sudo rpi-eeprom-update -a` followed by a reboot if an update is offered.

## Step 4. Turn on desktop auto login

```
sudo raspi-config
```

Go to System Options, then Boot / Auto Login, then Desktop Autologin. Finish, and answer No when it offers to reboot.

## Step 5. Install the display

Download the setup script from this repo and check that it arrived:

```
curl -fsSL https://raw.githubusercontent.com/anishoda/isoe-prayer-display/main/setup-pi.sh -o setup-pi.sh
chmod +x setup-pi.sh
ls -l setup-pi.sh
```

Then run it. For a horizontal TV:

```
sudo ./setup-pi.sh https://anishoda.github.io/isoe-prayer-display/
```

For a vertical TV, add the rotation value you chose (`90` or `270`):

```
sudo ROTATE=90 ./setup-pi.sh https://anishoda.github.io/isoe-prayer-display/
```

For the light theme, put the URL in quotes and add `?theme=light` at the end. After it finishes, reboot with `sudo reboot`.

What the script sets up:

- Chromium in full-screen kiosk mode on every boot, with the keyring prompt disabled.
- A nightly job at 02:40 that fetches the latest page. It checks that the download is the real display before replacing the working copy, so a wifi login page cannot replace good times with nonsense.
- A TV power schedule that runs every minute and follows the prayer timetable in the page.
- Screen blanking and the mouse pointer turned off.
- The desktop panel stopped at login. It is a Wi-Fi password agent, and a kiosk does not need it (see Step 7).
- Screen rotation, if you set `ROTATE`, kept in place by a script that re-applies it whenever the TV drops and restores its HDMI link.

## Step 6. Check the display and rotation

After the reboot, with the TV on the right input, the prayer times should appear on their own with no password prompt.

For a vertical TV, turn the TV on its side before you judge it. The page lays itself out as a tall board once the screen is rotated. To test a rotation value without a reboot, run this from the Pi's shell (not through `sudo`):

```
WAYLAND_DISPLAY=wayland-0 XDG_RUNTIME_DIR=/run/user/$(id -u) wlr-randr --output HDMI-A-1 --transform 90
```

If the picture is upside down for how you will mount the TV, use `270` instead and run the setup command again with `ROTATE=270`. After the next reboot, confirm the rotation was saved:

```
head -3 ~/.config/labwc/autostart
cat /opt/isoe-display/rotate.sh
```

The first line of the autostart file should call `/opt/isoe-display/rotate.sh`, and `rotate.sh` should not be empty. If the screen stays horizontal and `rotate.sh` is empty or missing, the setup stopped early: run it again.

The rotate script keeps running in the background. When the TV drops its HDMI link and restores it (switching off with the remote, standby, or the morning wake from the schedule), the screen resets to landscape, and the script puts it back within a few seconds. Test it before mounting: turn the TV off with its remote, wait ten seconds, turn it back on, and confirm the display returns in portrait.

To check the watcher on a Pi that is already installed, confirm it is running, then force the screen back to landscape. It should return to portrait on its own within a few seconds. Use the same rotation value you chose earlier:

```
pgrep -af rotate.sh
WAYLAND_DISPLAY=wayland-0 XDG_RUNTIME_DIR=/run/user/$(id -u) wlr-randr --output HDMI-A-1 --transform normal
```

If `pgrep` prints nothing, the Pi has an older `rotate.sh` that rotates once at login and then exits. Run the current `setup-pi.sh` again with `ROTATE` set, then reboot.

Before you drill anything, stand the TV on its side and walk past it from left to right. Budget LED panels wash out when viewed from the side, and rotating the TV turns that weak direction into the one people walk through.

## Step 7. Make the Wi-Fi connection permanent

Do this on every Pi, even if Wi-Fi seems to work. The Wi-Fi details entered in Imager become a connection profile that can lose its password after a restart. NetworkManager then asks for it, a "Wi-Fi Network Authentication Required" box appears over the prayer times, and the Pi drops off Raspberry Pi Connect until someone is standing at it.

The fix is a second connection profile that keeps the password in its own file and retries forever. Replace `NETWORK NAME` and `PASSWORD` with the masjid's, and keep the single quotes around the password:

```
sudo nmcli connection add type wifi ifname wlan0 con-name isoe-wifi ssid "NETWORK NAME" wifi-sec.key-mgmt wpa-psk wifi-sec.psk 'PASSWORD' wifi-sec.psk-flags 0 connection.autoconnect yes connection.autoconnect-retries 0 connection.autoconnect-priority 100
```

Check that it saved. The first command should list `isoe-wifi` with a file under `/etc/NetworkManager/system-connections`, and the second should show a `psk` line:

```
sudo nmcli -f NAME,FILENAME,AUTOCONNECT,AUTOCONNECT-PRIORITY connection show
sudo grep -i -E 'psk|flags' /etc/NetworkManager/system-connections/isoe-wifi.nmconnection
```

Then remove the old profile that Imager created, so it cannot prompt again. Find the file that defines it, move that file aside rather than deleting it (it contains the password), and delete the profile:

```
sudo grep -l -i wifis /etc/netplan/*.yaml
sudo mkdir -p /root/netplan-backup
sudo mv /etc/netplan/FILENAME.yaml /root/netplan-backup/
sudo nmcli connection delete "netplan-wlan0-NETWORK NAME"
```

Replace `FILENAME.yaml` with the name the first command printed, and use the exact profile name that `nmcli connection show` lists (it starts with `netplan-wlan0-`). Then reboot with `sudo reboot` and run `nmcli -f NAME,ACTIVE connection show`. `isoe-wifi` should be active, no box should appear on the TV, and the Pi should show as online in Connect. Test this once while you are next to the Pi.

Also stop cloud-init from regenerating the Wi-Fi profile, and tighten a file permission that NetworkManager warns about:

```
echo 'network: {config: disabled}' | sudo tee /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
sudo chmod 600 /lib/netplan/00-network-manager-all.yaml
```

The password box is shown by the desktop panel (`wf-panel-pi`), which acts as NetworkManager's password agent. If the Wi-Fi drops and authentication fails, the panel asks for the password and the box lands on top of the display. `setup-pi.sh` stops the panel at login. On a Pi installed earlier, run this once, reboot, then check that `pgrep -a wf-panel-pi` prints nothing:

```
echo "(sleep 8; pkill -f 'lwrespawn /usr/bin/wf-panel-pi'; pkill -x wf-panel-pi) &" >> ~/.config/labwc/autostart
```

To get logs if the Wi-Fi ever drops, make the journal persistent: `sudo mkdir -p /var/log/journal && sudo systemctl restart systemd-journald`. A network cable avoids Wi-Fi problems altogether, so use one wherever the TV has a jack nearby.

## Step 8. TV settings

Set these in the TV menu. The Vizio E48-C2 and E50-C1 use Menu, System, CEC, Enable. On the VQD55R-1004, look for CEC Device Control. If the menu offers One Touch Play or Input at Power On set to Last Used, turn them on.

- HDMI-CEC (called Anynet+, Bravia Sync or Device Control on other brands): on.
- Screen saver: off.
- Sleep timer and auto power off: off.
- Picture size: nothing cropped at the edges. Some TVs overscan and clip the top line.

## Step 9. Test the TV power control

Stop the scheduler first so it does not fight your test, then start it again at the end:

```
sudo systemctl stop isoe-display-tv.timer
echo 'scan' | cec-client -s -d 1 | head -30
echo 'standby 0' | cec-client -s -d 1
```

The scan should list your TV. After the TV goes to standby, wait a few minutes (ideally overnight on the first TV) and wake it:

```
echo 'on 0' | cec-client -s -d 1
```

If the TV wakes but shows its home screen instead of the Pi, send `echo 'as' | cec-client -s -d 1` to make the Pi the active source. The scheduler already does this about 8 seconds after waking the TV. Waking from standby is the part that varies by TV, so test it on every set before mounting. Then:

```
sudo systemctl start isoe-display-tv.timer
sudo /opt/isoe-display/tv-schedule.py --today
```

The second command prints today's on and off times. In November the TV turns off at about 21:00 and on at about 04:45. In late June it turns off at about 22:45 and on at about 03:45.

## Step 10. The test that matters

Pull the power on both the Pi and the TV, wait ten seconds, plug both back in, and walk away. Come back in three minutes. The TV should be on (or in standby if it is outside the schedule window) and the Pi should be showing the prayer display without anyone touching it. If it is not, the display is not ready for a wall.

## Per-TV test record

| TV | CEC standby works | CEC wake after hours works | Returns to Pi input | Rotation correct | Power-cut test passed |
| --- | --- | --- | --- | --- | --- |
| Vizio VQD55R-1004 | | | | | |
| Vizio E48-C2 (first unit) | | | | | |
| Vizio E48-C2 (second unit) | | | | | |
| Vizio E50-C1 | | | | | |

Vizio documents CEC on all three models, but standby, wake after several hours and return to the Pi input still need to be confirmed on each set.

## Troubleshooting

| Symptom | Cause and fix |
| --- | --- |
| Screen is blank late at night | The TV is probably in standby because the schedule turned it off. Wake it with the remote and pick the HDMI input. To override the schedule while testing, run `sudo systemctl stop isoe-display-tv.timer`. |
| Desktop shows, then a "Choose password for new keyring" box | Chromium or the Wi-Fi component wants a password store. If a Wi-Fi password box keeps coming back after restarts, see Step 7. Leave both boxes empty and choose Continue. `setup-pi.sh` prevents this with the `--password-store=basic` flag. To fix an already-installed Pi, run `sed -i 's\|--kiosk\|--kiosk --password-store=basic\|' ~/.config/labwc/autostart` and reboot. |
| Desktop shows but no prayer times | Check `ls -l /opt/isoe-display/`. If `display.html` is missing, the fetch failed: run `/opt/isoe-display/update.sh` and read the message. Check `pgrep -a chromium` to see whether the browser is running. |
| Still horizontal after a reboot | Setup was not run with `ROTATE`, or `rotate.sh` is empty. See Step 6. |
| No picture at all | Wrong TV input, or the cable is in the wrong Pi port. Use the port nearest the USB-C power connector. |
| Boots to a login screen | Auto login is off. Repeat Step 4. |
| TV will not wake by itself | CEC is off in the TV menu, or this TV does not wake from standby over CEC. The display still works, but you lose the morning wake. Run the scan in Step 9 to see whether the Pi can see the TV. |
| Imager: "Access denied" or read-only | See Step 1. |
| Red "times need updating" screen | The annual calendar ran out. See Keeping it running. |

Two Wi-Fi problems are covered in Step 7: a "Wi-Fi Network Authentication Required" box that covers the display after a restart, and a Pi that drops off Raspberry Pi Connect. Both come from the Wi-Fi password not being stored in the connection profile.

## Keeping it running

Nothing is needed day to day. Iqamah times change a few times a year and each Pi picks up the new page overnight. Keep the Pi on its own wall adapter so it can wake the TV, and shut it down properly (`sudo shutdown now`) rather than pulling the power when you can, since SD cards wear faster with hard power loss.

The current calendar runs to October 31, 2027. After that the display turns red and says the times need updating, and the TV schedule keeps the TV on so the warning is seen. The times are regenerated from the board's annual spreadsheet with `tools/gen-salah-display.py` in the ISOE working repo. Replace `index.html` in this repo, and every Pi will pick it up the next night.
