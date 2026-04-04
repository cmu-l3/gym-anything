#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Sales QBR Deck Result ==="

# Take final screenshot
su - ga -c "DISPLAY=:1 scrot /tmp/task_final_screenshot.png" || true

# Focus LibreOffice Impress window if open and force save
wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
    safe_xdotool ga :1 key --delay 300 ctrl+s
    sleep 3
    # Handle any format dialog (press Enter to accept default)
    safe_xdotool ga :1 key --delay 200 Return
    sleep 1
fi

# Check if ODP file was saved
if [ -f /home/ga/Documents/Presentations/qbr_q3_2023.odp ]; then
    echo "ODP file present: $(stat -c%s /home/ga/Documents/Presentations/qbr_q3_2023.odp) bytes"
else
    echo "WARNING: ODP file not found"
fi

# Check if PDF was exported
if [ -f /home/ga/Documents/Presentations/qbr_q3_2023.pdf ]; then
    echo "PDF present: $(stat -c%s /home/ga/Documents/Presentations/qbr_q3_2023.pdf) bytes"
else
    echo "PDF not found at expected path"
fi

echo "=== Export Complete ==="
