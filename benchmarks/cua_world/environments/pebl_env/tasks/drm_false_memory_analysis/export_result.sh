#!/bin/bash
# Export result for drm_false_memory_analysis

set -e
echo "=== Exporting drm_false_memory_analysis result ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Record task end time
date +%s > /tmp/task_end_timestamp

# Take final screenshot for evidence
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/drm_final_screenshot.png 2>/dev/null || true

echo "=== drm_false_memory_analysis export complete ==="