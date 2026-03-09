#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Cloud Migration Repair Result ==="

# Take final screenshot
su - ga -c "DISPLAY=:1 scrot /tmp/task_final_screenshot.png" || true

# Force save if LibreOffice is still open
wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
    safe_xdotool ga :1 key --delay 300 ctrl+s
    sleep 3
    # Handle any format dialog
    safe_xdotool ga :1 key --delay 200 Return
    sleep 1
fi

if [ -f /home/ga/Documents/Presentations/cloud_migration_deck.odp ]; then
    echo "ODP file present: $(stat -c%s /home/ga/Documents/Presentations/cloud_migration_deck.odp) bytes"
else
    echo "WARNING: ODP file not found"
fi

echo "=== Export Complete ==="
