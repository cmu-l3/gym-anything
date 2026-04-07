#!/bin/bash
# Export result for pebl_ant_script_repair_and_run
# The verifier reads the .pbl file and bug_report.txt directly via copy_from_env

set -e
echo "=== Exporting pebl_ant_script_repair_and_run result ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

date +%s > /tmp/task_end_timestamp

# Take final screenshot for evidence
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/ant_final_screenshot.png 2>/dev/null || true

echo "=== pebl_ant_script_repair_and_run export complete ==="
