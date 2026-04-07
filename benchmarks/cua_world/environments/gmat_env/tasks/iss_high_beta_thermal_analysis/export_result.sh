#!/bin/bash
set -euo pipefail

echo "=== Exporting iss_high_beta_thermal_analysis results ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

REPORT_PATH="/home/ga/GMAT_output/iss_beta_report.txt"

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Find the most recently modified script file in the user's home directory
echo "Looking for agent's GMAT script..."
AGENT_SCRIPT=$(find /home/ga -type f -name "*.script" -newermt "@$TASK_START" 2>/dev/null | head -1 || echo "")
SCRIPT_EXISTS="false"
if [ -n "$AGENT_SCRIPT" ] && [ -f "$AGENT_SCRIPT" ]; then
    echo "Found script at $AGENT_SCRIPT"
    cp "$AGENT_SCRIPT" /tmp/agent_script.script
    chmod 644 /tmp/agent_script.script
    SCRIPT_EXISTS="true"
else
    echo "No recently modified .script file found."
fi

# Check report file
REPORT_EXISTS="false"
REPORT_CREATED_DURING="false"
MAX_BETA_VAL="0"
HIGH_BETA_DAYS_VAL="0"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH")
    if [ "$REPORT_MTIME" -ge "$TASK_START" ]; then
        REPORT_CREATED_DURING="true"
    fi
    
    # Extract values from report
    MAX_BETA_VAL=$(grep -oP 'Max_Beta_Angle_deg:\s*\K[0-9]+\.?[0-9]*' "$REPORT_PATH" 2>/dev/null | head -1 || echo "0")
    HIGH_BETA_DAYS_VAL=$(grep -oP 'High_Beta_Days:\s*\K[0-9]+' "$REPORT_PATH" 2>/dev/null | head -1 || echo "0")
fi

APP_RUNNING=$(pgrep -f "GMAT" > /dev/null && echo "true" || echo "false")

# Extract trajectory screenshots (handled by framework, but we ensure app state here)
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "script_exists": $SCRIPT_EXISTS,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING,
    "max_beta_angle_deg": "$MAX_BETA_VAL",
    "high_beta_days": "$HIGH_BETA_DAYS_VAL",
    "report_path": "$REPORT_PATH"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete."
cat /tmp/task_result.json
echo "=== Export Done ==="