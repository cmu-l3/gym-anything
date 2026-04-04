#!/usr/bin/env bash
# set -euo pipefail

echo "=== OSWorld Chrome Task Export: 35253b65-1c19-4304-8aa4-6884b8218fc0 ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq sqlite3 || true

# Focus Chrome window
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Check for desktop shortcuts (list .desktop files)
echo "Checking for desktop shortcuts..."
DESKTOP_DIR="/home/ga/Desktop"
if [ -d "$DESKTOP_DIR" ]; then
    # Find all .desktop files and extract their Exec lines
    find "$DESKTOP_DIR" -name "*.desktop" -type f | while read -r desktop_file; do
        if [ -f "$desktop_file" ]; then
            grep "^Exec=" "$desktop_file" 2>/dev/null || echo "No Exec line"
        fi
    done > /tmp/shortcuts_exec.txt
    echo "Desktop shortcuts exported to /tmp/shortcuts_exec.txt"
    # Also create a dummy URL file for compatibility
    echo "desktop:shortcuts" > /tmp/final_url.txt
else
    echo "No desktop directory found"
    echo "no-desktop" > /tmp/final_url.txt
fi

# Take a final screenshot
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

echo "✅ Export complete"
