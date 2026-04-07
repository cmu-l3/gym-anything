#!/bin/bash
echo "=== Exporting PVT Vigilance Decrement Analysis result ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Record task end time
date +%s > /tmp/task_end_timestamp

# Take final screenshot for evidence
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/pvt_final_screenshot.png 2>/dev/null || true

echo "=== Export complete ==="