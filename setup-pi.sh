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
grep -q "ISOE Prayer Times" "\$TMP" || { echo "no title marker, ignoring"; exit 1; }
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
CHROME_FLAGS="--kiosk --password-store=basic --noerrdialogs --disable-infobars --disable-session-crashed-bubble \
--disable-features=Translate --check-for-update-interval=31536000 \
--autoplay-policy=no-user-gesture-required --start-fullscreen"
CHROMIUM="$(command -v chromium || command -v chromium-browser || true)"
[ -n "$CHROMIUM" ] || { echo "no chromium binary found after install"; exit 1; }
LAUNCH="$CHROMIUM $CHROME_FLAGS file://$PAGE"

# Screen rotation. The connector is named HDMI-A-1 under Wayland and HDMI-1
# under X11, and which one exists depends on the Pi OS image, so try each and
# keep the first that takes.
if [ "$ROTATE" != "0" ]; then
  case "$ROTATE" in 90) XDIR=left;; 180) XDIR=inverted;; 270) XDIR=right;; esac
  cat > "$APP/rotate.sh" <<ROT
#!/usr/bin/env bash
# Keep the screen rotated. When the TV drops its HDMI link (standby, power off,
# the nightly schedule) the compositor resets the rotation, so a one-shot
# command at login is not enough: re-apply it whenever it goes back to normal.
T=$ROTATE
if command -v wlr-randr >/dev/null 2>&1 && [ -n "\${WAYLAND_DISPLAY:-}" ]; then
  while true; do
    if wlr-randr 2>/dev/null | grep -q 'Transform: *normal'; then
      for o in HDMI-A-1 HDMI-A-2; do
        wlr-randr --output \$o --transform \$T 2>/dev/null && break
      done
    fi
    sleep 3
  done
fi
# X11 sessions: rotate once, retrying while the display comes up.
for try in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  for o in HDMI-1 HDMI-2; do
    xrandr --output \$o --rotate $XDIR 2>/dev/null && exit 0
  done
  sleep 1
done
exit 0
ROT
  chmod +x "$APP/rotate.sh"
  ROTCMD="$APP/rotate.sh &"
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
# TV power via HDMI-CEC, following the prayer timetable inside the page:
# on 30 min before Fajr adhan, off 60 min after Isha iqamah. (The old fixed
# 04:30 / 21:45 cron was wrong for about four months of the year.)
# ---------------------------------------------------------------------------
rm -f /etc/cron.d/isoe-display-tv
if [ "$HAVE_CEC" = "1" ]; then
  echo "==> TV schedule follows prayer times (HDMI-CEC)"
  cat > "$APP/tv-schedule.py" <<'TVPY'
#!/usr/bin/env python3
"""ISOE prayer display: switch the TV on and off over HDMI-CEC to follow the
prayer timetable baked into the display page itself.

  TV on   30 minutes before Fajr adhan
  TV off  60 minutes after Isha iqamah

Run every minute from a systemd timer. It works out what state the TV should be
in right now and only sends a command when that differs from the last one it
sent, so a reboot or power cut mid-night puts the TV back in the right state
within a minute. Reads the same file the kiosk shows, so the TV and the screen
can never disagree about the times.

  tv-schedule.py                  normal run
  tv-schedule.py --today          print today's on/off times and exit
  tv-schedule.py --at 2027-06-19T22:50 --dry-run   what would happen then
"""
import argparse, datetime as dt, json, os, re, subprocess, sys, time
from zoneinfo import ZoneInfo

PAGE = os.environ.get("ISOE_PAGE", "/opt/isoe-display/display.html")
STATE = os.environ.get("ISOE_STATE", "/var/lib/isoe-display/tv-state")
TZ = ZoneInfo("America/Los_Angeles")
ON_BEFORE_FAJR = 30    # minutes
OFF_AFTER_ISHA = 60    # minutes
FAJR_ADHAN, ISHA_IQAMA = 0, 10   # column order used by the page's data array


def load(path):
    s = open(path, encoding="utf-8").read()
    d = json.loads(re.search(r"var D = (\[\[.*?\]\]);", s, re.S).group(1))
    start = re.search(r'var START = "(\d{4}-\d{2}-\d{2})"', s).group(1)
    ndays = int(re.search(r"NDAYS = (\d+)", s).group(1))
    cols = []
    for c in d:                       # delta-encoded: running sum per column
        o = [c[0]]
        for v in c[1:]:
            o.append(o[-1] + v)
        cols.append(o)
    return cols, dt.date.fromisoformat(start), ndays


def window(cols, start, ndays, day):
    i = (day - start).days
    if not 0 <= i < ndays:
        return None
    return cols[FAJR_ADHAN][i] - ON_BEFORE_FAJR, cols[ISHA_IQAMA][i] + OFF_AFTER_ISHA


def hm(m):
    return f"{m // 60:02d}:{m % 60:02d}"


def desired(cols, start, ndays, now):
    w = window(cols, start, ndays, now.date())
    if w is None:
        return "on"   # calendar ran out: keep the screen up so the red warning is seen
    m = now.hour * 60 + now.minute
    return "on" if w[0] <= m < w[1] else "off"


def cec(cmd):
    r = subprocess.run(["cec-client", "-s", "-d", "1"], input=cmd + "\n",
                       text=True, capture_output=True, timeout=45)
    return r.returncode == 0


def send(state):
    if state == "off":
        return cec("standby 0")
    ok = cec("on 0")
    time.sleep(8)            # let the TV finish waking, then claim its input
    return cec("as") and ok


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--today", action="store_true")
    ap.add_argument("--at", help="pretend it is this local time (YYYY-MM-DDTHH:MM)")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    cols, start, ndays = load(PAGE)
    now = dt.datetime.fromisoformat(a.at).replace(tzinfo=TZ) if a.at else dt.datetime.now(TZ)

    if a.today:
        w = window(cols, start, ndays, now.date())
        print("calendar ended, TV stays on" if w is None else
              f"{now.date()}  TV on {hm(w[0])}  off {hm(w[1])}")
        return 0

    want = desired(cols, start, ndays, now)
    try:
        last = open(STATE).read().strip()
    except OSError:
        last = ""
    if want == last:
        return 0
    print(f"{now:%F %R} TV should be {want} (was {last or 'unknown'})", flush=True)
    if a.dry_run:
        return 0
    if send(want):
        os.makedirs(os.path.dirname(STATE), exist_ok=True)
        open(STATE, "w").write(want)
        return 0
    print("cec command failed, will retry next minute", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
TVPY
  chmod +x "$APP/tv-schedule.py"
  cat > /etc/systemd/system/isoe-display-tv.service <<SVC
[Unit]
Description=ISOE prayer display TV power schedule
[Service]
Type=oneshot
ExecStart=/usr/bin/python3 $APP/tv-schedule.py
StateDirectory=isoe-display
SVC
  cat > /etc/systemd/system/isoe-display-tv.timer <<TMR
[Unit]
Description=Check ISOE TV power schedule every minute
[Timer]
OnBootSec=60
OnCalendar=minutely
AccuracySec=5s
[Install]
WantedBy=timers.target
TMR
  systemctl daemon-reload
  systemctl enable --now isoe-display-tv.timer
else
  echo "==> no cec-client, skipping the TV on/off schedule"
fi

cat <<DONE

==> done.

   page        $PAGE
   update      $APP/update.sh          (timer: isoe-display-update.timer)
   TV schedule $APP/tv-schedule.py  (timer: isoe-display-tv.timer)
               check:  sudo $APP/tv-schedule.py --today

   Reboot to start the kiosk:   sudo reboot

   Check things afterwards:
     systemctl status isoe-display-update.timer
     $APP/update.sh                   # force an update now
     echo 'on 0' | cec-client -s -d 1 # test TV wake

   Screen blanking: if the screen still sleeps, turn it off in
   sudo raspi-config -> Display Options -> Screen Blanking.
DONE
