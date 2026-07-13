#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${WEIRD_CAPTCHA_STATE_DIR:-/tmp/weird_captcha_gym}"
PORT="${WEIRD_CAPTCHA_PORT:-8787}"
URL="http://127.0.0.1:${PORT}/?task=$(date +%s)"

mkdir -p "$STATE_DIR"

browser_cmd=""
for candidate in google-chrome-stable google-chrome chromium chromium-browser firefox /snap/bin/firefox; do
  if command -v "$candidate" >/dev/null 2>&1 || [ -x "$candidate" ]; then
    browser_cmd="$candidate"
    break
  fi
done

if [ -z "$browser_cmd" ]; then
  echo "No browser command found for Weird CAPTCHA Gym." | tee -a /tmp/weird_captcha_browser.log
  exit 0
fi

launch_as_user="root"
home_dir="/root"
if id ga >/dev/null 2>&1; then
  launch_as_user="ga"
  home_dir="/home/ga"
fi

xauth=""
for candidate in "$home_dir/.Xauthority" "/run/user/1000/gdm/Xauthority"; do
  if [ -f "$candidate" ]; then
    xauth="$candidate"
    break
  fi
done

profile_dir="$home_dir/.weird-captcha-profile"
mkdir -p "$profile_dir"
chown -R "$launch_as_user:$launch_as_user" "$profile_dir" 2>/dev/null || true

if command -v xhost >/dev/null 2>&1; then
  DISPLAY=:1 xhost +SI:localuser:"$launch_as_user" >/dev/null 2>&1 || true
fi

env_prefix="DISPLAY=:1 HOME=$home_dir"
if [ -n "$xauth" ]; then
  env_prefix="$env_prefix XAUTHORITY=$xauth"
fi

if [[ "$browser_cmd" == *firefox ]]; then
  launch="$env_prefix $browser_cmd --new-window '$URL'"
else
  launch="$env_prefix $browser_cmd --app='$URL' --window-size=1280,720 --force-device-scale-factor=1 --no-first-run --no-default-browser-check --disable-background-networking --disable-sync --disable-infobars --disable-session-crashed-bubble --hide-crash-restore-bubble --no-sandbox --disable-dev-shm-usage --user-data-dir='$profile_dir'"
fi

echo "Launching puzzle browser as $launch_as_user via $browser_cmd -> $URL" >> /tmp/weird_captcha_browser.log
if [ "$launch_as_user" = "root" ]; then
  nohup bash -lc "$launch" >> /tmp/weird_captcha_browser.log 2>&1 &
else
  nohup sudo -u "$launch_as_user" bash -lc "$launch" >> /tmp/weird_captcha_browser.log 2>&1 &
fi

for _ in $(seq 1 60); do
  if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -Eiq 'firefox|mozilla|chrom|weird captcha|machine eligibility'; then
    DISPLAY=:1 wmctrl -r "Weird CAPTCHA Gym" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -r "Machine Eligibility" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -a "Weird CAPTCHA Gym" 2>/dev/null || true
    DISPLAY=:1 wmctrl -a "Machine Eligibility" 2>/dev/null || true
    echo "Puzzle browser window detected." >> /tmp/weird_captcha_browser.log
    exit 0
  fi
  sleep 0.5
done

echo "Puzzle browser window was not detected before timeout." >> /tmp/weird_captcha_browser.log
DISPLAY=:1 wmctrl -l >> /tmp/weird_captcha_browser.log 2>&1 || true
