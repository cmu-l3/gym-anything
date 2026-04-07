#!/bin/bash
# Export result for simon_delta_plot_analysis
# The verifier dynamically calculates ground truth from the CSV and checks the output JSON.

set -e
echo "=== Exporting simon_delta_plot_analysis result ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Record task end time
date +%s > /tmp/task_end_timestamp

# Take final screenshot for visual evidence mapping
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/simon_final_screenshot.png 2>/dev/null || true

echo "=== simon_delta_plot_analysis export complete ==="