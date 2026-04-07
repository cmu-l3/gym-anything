#!/bin/bash
# Export result for audiovisual_toj_psychometric_analysis
# The verifier reads the JSON output directly from the environment.

set -e
echo "=== Exporting audiovisual_toj_psychometric_analysis result ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Record task end time
date +%s > /tmp/task_end_timestamp

# Take final screenshot for evidence
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/toj_final_screenshot.png 2>/dev/null || true

echo "=== audiovisual_toj_psychometric_analysis export complete ==="