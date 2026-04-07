#!/bin/bash
# Export result for bart_risk_adjustment_report
# The verifier reads the output JSON directly from the environment using copy_from_env

set -e
echo "=== Exporting bart_risk_adjustment_report result ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Record task end time
date +%s > /tmp/task_end_timestamp

# Take final screenshot for evidence
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/bart_final_screenshot.png 2>/dev/null || true

echo "=== bart_risk_adjustment_report export complete ==="
