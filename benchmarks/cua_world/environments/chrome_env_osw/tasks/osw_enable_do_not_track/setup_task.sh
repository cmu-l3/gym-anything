#!/bin/bash
set -e
echo "=== Setting up osw_enable_do_not_track task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Kill any existing Chrome processes
pkill -f chrome || true
sleep 2

# 2. Reset Chrome profile to clean state with Do Not Track DISABLED
CDP_DIR="/home/ga/.config/google-chrome-cdp"
CHROME_DIR="/home/ga/.config/google-chrome"

for PROFILE_DIR in "$CDP_DIR" "$CHROME_DIR"; do
    if [ -d "$PROFILE_DIR" ]; then
        rm -rf "$PROFILE_DIR"
    fi
    mkdir -p "$PROFILE_DIR/Default"
    chown -R ga:ga "$PROFILE_DIR"

    # Write default preferences with Do Not Track DISABLED
    cat > "$PROFILE_DIR/Default/Preferences" << 'PREFEOF'
{
    "browser": {
        "show_home_button": true
    },
    "homepage": "https://www.google.com",
    "homepage_is_newtabpage": false,
    "enable_do_not_track": false,
    "safebrowsing": {
        "enabled": true,
        "enhanced": false
    },
    "download": {
        "prompt_for_download": false,
        "default_directory": "/home/ga/Downloads"
    },
    "webkit": {
        "webprefs": {
            "default_font_size": 16,
            "default_fixed_font_size": 13,
            "minimum_font_size": 0
        }
    }
}
PREFEOF
    chown -R ga:ga "$PROFILE_DIR"
done

# 3. Launch Chrome with CDP
su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh about:blank" &
sleep 5

# Wait for Chrome window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i -E "chrome|chromium"; then
        break
    fi
    sleep 1
done

# Maximize and focus Chrome
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Chrome" 2>/dev/null || true
sleep 1

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="
