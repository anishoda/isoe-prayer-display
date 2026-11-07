#!/usr/bin/env bash
# ISOE musallah prayer display: one-time setup for a Raspberry Pi running
# Raspberry Pi OS (Bookworm, 64-bit, Desktop) with auto-login enabled.
#
#   curl -fsSL <url>/setup-pi.sh -o setup-pi.sh
#   chmod +x setup-pi.sh
#   sudo ./setup-pi.sh https://display.isoeastvale.org/display.html
#
# Pass the published URL as the first argument. If you leave it off, the Pi
# just runs whatever display.html you have copied into /opt/isoe-display.
#
# For a TV hung sideways, rotate the output:
#   sudo ROTATE=90  ./setup-pi.sh        # top of the picture to the LEFT
#   sudo ROTATE=270 ./setup-pi.sh        # top of the picture to the RIGHT
# The page lays itself out for portrait on its own; this only turns the screen.
set -euo pipefail

URL="${1:-}"
ROTATE="${ROTATE:-0}"
case "$ROTATE" in 0|90|180|270) ;; *) echo "ROTATE must be 0, 90, 180 or 270"; exit 1;; esac
KIOSK_USER="${SUDO_USER:-pi}"
HOME_DIR="$(getent passwd "$KIOSK_USER" | cut -d: -f6)"
APP=/opt/isoe-display
PAGE="$APP/display.html"

[ "$(id -u)" -eq 0 ] || { echo "run with sudo"; exit 1; }

echo "==> installing packages"
apt-get update -qq
apt-get install -y --no-install-recommends \
  chromium-browser unclutter curl ca-certificates wlr-randr x11-xserver-utils
# cec-utils is packaged differently across Debian releases, and the display
# works fine without it (you just lose the TV on/off schedule), so never let a
# missing package abort the install.
HAVE_CEC=1
apt-get install -y --no-install-recommends cec-utils 2>/dev/null || \
  apt-get install -y --no-install-recommends libcec6 2>/dev/null || HAVE_CEC=0
command -v cec-client >/dev/null 2>&1 || HAVE_CEC=0

echo "==> creating $APP"
install -d -o "$KIOSK_USER" -g "$KIOSK_USER" "$APP"

# ---------------------------------------------------------------------------
# Updater. Fetches the published page to a temp file, refuses to install
# anything that does not look like the real display, then swaps it in
# atomically. A bad fetch leaves yesterday's working copy untouched, which is
# the whole point: the wall must never go blank because the wifi did.
# ---------------------------------------------------------------------------
cat > "$APP/update.sh" <<UPD
#!/usr/bin/env bash
set -euo pipefail
URL="\${1:-${URL}}"
[ -n "\$URL" ] || exit 0
TMP=\$(mktemp)
trap 'rm -f "\$TMP"' EXIT
curl -fsSL --max-time 60 "\$URL" -o "\$TMP"
# sanity gates: real size, our marker, and a decoded payload
[ "\$(stat -c%s "\$TMP")" -gt 8000 ] || { echo "too small, ignoring"; exit 1; }
grep -q "gen-salah-display.py" "\$TMP"  || { echo "not the display page, ignoring"; exit 1; }
grep -q "Islamic Society of Eastvale" "\$TMP" || { echo "no org marker, ignoring"; exit 1; }
if ! cmp -s "\$TMP" "$PAGE"; then
  cp "\$TMP" "$PAGE"
  echo "\$(date -Is) updated from \$URL"
else
  echo "\$(date -Is) already current"
fi
UPD
chmod +x "$APP/update.sh"
chown "$KIOSK_USER:$KIOSK_USER" "$APP/update.sh"

# Seed from a display.html sitting next to this script, so the wall works
# before any hosting exists.
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$SRC_DIR/display.html" ]; then
  echo "==> seeding from $SRC_DIR/display.html"
  cp "$SRC_DIR/display.html" "$PAGE"
  chown "$KIOSK_USER:$KIOSK_USER" "$PAGE"
fi

if [ -n "$URL" ]; then
  echo "==> first fetch from $URL"
  sudo -u "$KIOSK_USER" "$APP/update.sh" "$URL" || \
    echo "    fetch failed, keeping the seeded copy."
fi

if [ ! -s "$PAGE" ]; then
  echo "!!  no display.html yet. Put one at $PAGE before rebooting."
fi

echo "==> nightly update at 02:40 (before the page's own 03:00 reload)"
cat > /etc/systemd/system/isoe-display-update.service <<SVC
[Unit]
Description=Fetch latest ISOE prayer display
After=network-online.target
Wants=network-online.target
[Service]
Type=oneshot
User=$KIOSK_USER
ExecStart=$APP/update.sh
SVC
cat > /etc/systemd/system/isoe-display-update.timer <<TMR
[Unit]
Description=Nightly ISOE prayer display update
[Timer]
OnCalendar=*-*-* 02:40:00
Persistent=true
RandomizedDelaySec=600
[Install]
WantedBy=timers.target
TMR
systemctl daemon-reload
systemctl enable --now isoe-display-update.timer

# ---------------------------------------------------------------------------
# Kiosk autostart. Pi OS Bookworm ships labwc or wayfire depending on model and
# image date, and older images use X11/LXDE, so write all three. Only the one
# in use is read.
# ---------------------------------------------------------------------------
echo "==> kiosk autostart for user $KIOSK_USER"
CHROME_FLAGS="--kiosk --noerrdialogs --disable-infobars --disable-session-crashed-bubble \
--disable-features=Translate --check-for-update-interval=31536000 \
--autoplay-policy=no-user-gesture-required --start-fullscreen"
LAUNCH="chromium-browser $CHROME_FLAGS file://$PAGE"

# Screen rotation. The connector is named HDMI-A-1 under Wayland and HDMI-1
# under X11, and which one exists depends on the Pi OS image, so try each and
# keep the first that takes.
if [ "$ROTATE" != "0" ]; then
  case "$ROTATE" in 90) XDIR=left;; 180) XDIR=inverted;; 270) XDIR=right;; esac
  cat > "$APP/rotate.sh" <<ROT
#!/usr/bin/env bash
for o in HDMI-A-1 HDMI-A-2; do
  wlr-randr --output \\$o --transform $ROTATE 2>/dev/null && exit 0
done
for o in HDMI-1 HDMI-2; do
  xrandr --output \\$o --rotate $XDIR 2>/dev/null && exit 0
done
exit 0
ROT
  chmod +x "$APP/rotate.sh"
  ROTCMD="$APP/rotate.sh"
  echo "==> screen rotation $ROTATE degrees"
else
  ROTCMD="true"
fi

sudo -u "$KIOSK_USER" mkdir -p "$HOME_DIR/.config/labwc" \
     "$HOME_DIR/.config/autostart" "$HOME_DIR/.config/wayfire.ini.d" 2>/dev/null || true

# labwc
cat > "$HOME_DIR/.config/labwc/autostart" <<LAB
$ROTCMD
unclutter -idle 0 &
$LAUNCH &
LAB
chmod +x "$HOME_DIR/.config/labwc/autostart"

# wayfire
if [ -f "$HOME_DIR/.config/wayfire.ini" ] && ! grep -q isoe "$HOME_DIR/.config/wayfire.ini"; then
  printf '\n[autostart]\nisoe = %s\nunclutter = unclutter -idle 0\nscreensaver = false\ndpms = false\n' \
    "$LAUNCH" >> "$HOME_DIR/.config/wayfire.ini"
fi

# X11 / LXDE
cat > "$HOME_DIR/.config/autostart/isoe-display.desktop" <<DSK
[Desktop Entry]
Type=Application
Name=ISOE Prayer Display
Exec=sh -c "$ROTCMD; $LAUNCH"
X-GNOME-Autostart-enabled=true
DSK
cat > "$HOME_DIR/.config/autostart/isoe-noblank.desktop" <<DSK
[Desktop Entry]
Type=Application
Name=Disable blanking
Exec=sh -c "xset s off; xset -dpms; xset s noblank"
DSK
chown -R "$KIOSK_USER:$KIOSK_USER" "$HOME_DIR/.config"

# ---------------------------------------------------------------------------
# TV power via HDMI-CEC. Saves the panel and the power bill, and means nobody
# has to find the remote. Times are deliberately wide of Fajr and Isha.
# ---------------------------------------------------------------------------
if [ "$HAVE_CEC" = "1" ]; then
  echo "==> TV on 04:30, off 21:45 (HDMI-CEC)"
  cat > /etc/cron.d/isoe-display-tv <<'CRN'
SHELL=/bin/bash
30 4 * * *  root  echo 'on 0'      | cec-client -s -d 1 >/dev/null 2>&1
45 21 * * * root  echo 'standby 0' | cec-client -s -d 1 >/dev/null 2>&1
CRN
else
  echo "==> no cec-client, skipping the TV on/off schedule"
fi

cat <<DONE

==> done.

   page        $PAGE
   update      $APP/update.sh          (timer: isoe-display-update.timer)
   TV schedule /etc/cron.d/isoe-display-tv  (only if cec-client installed)

   Reboot to start the kiosk:   sudo reboot

   Check things afterwards:
     systemctl status isoe-display-update.timer
     $APP/update.sh                   # force an update now
     echo 'on 0' | cec-client -s -d 1 # test TV wake

   Screen blanking: if the screen still sleeps, turn it off in
   sudo raspi-config -> Display Options -> Screen Blanking.
DONE
