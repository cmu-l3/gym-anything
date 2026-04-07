#!/bin/bash
set -e
echo "=== Exporting hicks_law_information_processing result ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Record task end timestamp
date +%s > /tmp/task_end_timestamp

# Capture final screenshot for evidence
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/hicks_final_screenshot.png 2>/dev/null || true

echo "=== hicks_law_information_processing export complete ==="