#!/bin/bash
# Export result for ospan_scoring_analysis

set -e
echo "=== Exporting ospan_scoring_analysis result ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Record task end time
date +%s > /tmp/task_end_timestamp

# Take final screenshot for evidence
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/ospan_final_screenshot.png 2>/dev/null || true

echo "=== ospan_scoring_analysis export complete ==="