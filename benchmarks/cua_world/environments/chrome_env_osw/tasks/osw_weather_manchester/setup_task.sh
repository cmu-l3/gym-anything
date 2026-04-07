#!/bin/bash
set -e
echo "=== Setting up osw_weather_manchester task ==="

date +%s > /tmp/task_start_time.txt

pkill -f chrome || true
sleep 2

CDP_DIR="/home/ga/.config/google-chrome-cdp"
CHROME_DIR="/home/ga/.config/google-chrome"

for PROFILE_DIR in "$CDP_DIR" "$CHROME_DIR"; do
    if [ -d "$PROFILE_DIR" ]; then
        rm -rf "$PROFILE_DIR"
    fi
    mkdir -p "$PROFILE_DIR/Default"
    chown -R ga:ga "$PROFILE_DIR"

    cat > "$PROFILE_DIR/Default/Preferences" << 'PREFEOF'
{
    "browser": {
        "show_home_button": true
    },
    "homepage": "https://www.google.com",
    "homepage_is_newtabpage": false,
    "safebrowsing": {
        "enabled": true,
        "enhanced": false
    },
    "download": {
        "prompt_for_download": false,
        "default_directory": "/home/ga/Downloads"
    }
}
PREFEOF
    chown -R ga:ga "$PROFILE_DIR"
done

su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh about:blank" &
sleep 5

for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i -E "chrome|chromium"; then
        break
    fi
    sleep 1
done

sleep 2
su - ga -c "DISPLAY=:1 xdotool key ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers 'https://www.accuweather.com/'" || true
su - ga -c "DISPLAY=:1 xdotool key Return" || true
sleep 3

DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Chrome" 2>/dev/null || true
sleep 1

DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="
