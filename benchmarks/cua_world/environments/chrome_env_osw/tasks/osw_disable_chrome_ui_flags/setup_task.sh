#!/bin/bash
set -e
echo "=== Setting up osw_disable_chrome_ui_flags task ==="

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

    # Write default Preferences
    cat > "$PROFILE_DIR/Default/Preferences" << 'PREFEOF'
{
    "browser": {
        "show_home_button": true
    },
    "homepage": "https://www.google.com",
    "homepage_is_newtabpage": false,
    "download": {
        "prompt_for_download": false,
        "default_directory": "/home/ga/Downloads"
    }
}
PREFEOF

    # Write Local State with the chrome-refresh-2023 experiments ENABLED
    # (The agent's task is to DISABLE these, so they must start enabled)
    # Note: Local State goes in the parent dir, not Default/
    cat > "$PROFILE_DIR/Local State" << 'LSEOF'
{
    "browser": {
        "enabled_labs_experiments": [
            "chrome-refresh-2023@1",
            "chrome-webui-refresh-2023@1"
        ]
    }
}
LSEOF
    chown -R ga:ga "$PROFILE_DIR"
done

su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh about:blank" &
sleep 8

for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i -E "chrome|chromium"; then
        break
    fi
    sleep 1
done

DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Chrome" 2>/dev/null || true
sleep 1

DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="
