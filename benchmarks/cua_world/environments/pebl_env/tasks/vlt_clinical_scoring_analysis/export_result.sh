#!/bin/bash
# Export result for vlt_clinical_scoring_analysis
# The verifier reads the JSON output directly from the environment using copy_from_env

set -e
echo "=== Exporting vlt_clinical_scoring_analysis result ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Record task end time
date +%s > /tmp/task_end_timestamp

# Take final screenshot for evidence
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/vlt_final_screenshot.png 2>/dev/null || true

echo "=== vlt_clinical_scoring_analysis export complete ==="