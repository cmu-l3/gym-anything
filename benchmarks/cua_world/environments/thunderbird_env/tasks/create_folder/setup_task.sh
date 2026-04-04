#!/bin/bash
set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Create Folder Task ==="

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

echo "=== Create Folder Task Setup Complete ==="
echo "📁 Instructions:"
echo "  1. Right-click on 'Local Folders' in the folder pane"
echo "  2. Select 'New Folder...' from the context menu"
echo "  3. Enter folder name: Work"
echo "  4. Click 'Create Folder' or press Enter"
