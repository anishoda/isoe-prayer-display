# ISOE prayer display

Full-screen prayer times board for the Islamic Society of Eastvale musallah.

**Live:** https://anishoda.github.io/isoe-prayer-display/

A single self-contained HTML file. The whole annual prayer calendar is
delta-encoded into the page, so once it loads it needs no network at all. That
is deliberate: a prayer display that goes blank because the wifi dropped during
Fajr is worse than a printed sheet.

## Options

| URL | |
| --- | --- |
| `/` | dark theme |
| `/?theme=light` | light theme |

The page detects portrait by itself, so a TV hung sideways needs no setting.

## Running it on a wall

Point any browser at the link in kiosk mode. Setup notes for a Raspberry Pi,
including screen rotation and switching the TV on and off by HDMI-CEC, live in
the ISOE working repo alongside the generator.

## Updating

Times are generated from the board's annual spreadsheet by
`tools/gen-salah-display.py` in the ISOE working repo. Regenerate, then replace
`index.html` here.

**The current calendar runs to October 31, 2027.** After that the display
covers itself in a red warning rather than showing the wrong times.
