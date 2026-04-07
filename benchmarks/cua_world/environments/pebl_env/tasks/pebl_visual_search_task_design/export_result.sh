#!/bin/bash
# Export result for pebl_visual_search_task_design

set -e
echo "=== Exporting pebl_visual_search_task_design result ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

date +%s > /tmp/task_end_timestamp
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/visual_search_final_screenshot.png 2>/dev/null || true

echo "=== pebl_visual_search_task_design export complete ==="
