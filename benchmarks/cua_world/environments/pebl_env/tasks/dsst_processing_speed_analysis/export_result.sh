#!/bin/bash
set -e
echo "=== Exporting DSST task result ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Record task end time
date +%s > /tmp/task_end_timestamp

# Take final screenshot for visual confirmation
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/dsst_final_screenshot.png 2>/dev/null || true

echo "=== export complete ==="