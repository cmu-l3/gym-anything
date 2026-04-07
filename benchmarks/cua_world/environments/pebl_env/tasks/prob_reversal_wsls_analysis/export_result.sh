#!/bin/bash
# Export result for prob_reversal_wsls_analysis

set -e
echo "=== Exporting prob_reversal_wsls_analysis result ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Record task end time
date +%s > /tmp/task_end_timestamp

# Take final screenshot for evidence
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/reversal_final_screenshot.png 2>/dev/null || true

echo "=== prob_reversal_wsls_analysis export complete ==="