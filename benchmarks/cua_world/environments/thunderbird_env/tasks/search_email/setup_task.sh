#!/bin/bash
set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Search Email Task ==="

# Wait for Thunderbird to be ready
if ! wait_for_thunderbird_ready 30; then
    echo "ERROR: Thunderbird not ready"
fi

# Click center of desktop to focus it
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus Thunderbird window
echo "Focusing Thunderbird window..."
wid=$(get_thunderbird_window_id)
if [ -n "$wid" ]; then
    if focus_window "$wid"; then
        # Maximize window
        safe_xdotool ga :1 key F11
        sleep 0.5
    fi
fi

# Navigate to Inbox
echo "Navigating to Inbox..."
su - ga -c "DISPLAY=:1 wmctrl -a Thunderbird" || true
sleep 0.3

echo "=== Search Email Task Setup Complete ==="
echo "🔍 Instructions:"
echo "  1. Use the search box (Ctrl+K or click search box at top)"
echo "  2. Type: Welcome to Thunderbird"
echo "  3. Press Enter to search"
echo "  4. Click on the found email to select it"
echo "  5. Mark the email as starred/flagged (press 'S' or click star icon)"
