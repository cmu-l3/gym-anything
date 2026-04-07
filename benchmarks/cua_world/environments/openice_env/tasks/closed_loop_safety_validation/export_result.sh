#!/bin/bash
echo "=== Exporting Closed Loop Safety Validation result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot (framework requirement)
take_screenshot /tmp/task_final_screenshot.png

# Timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Check Artifact Existence
EXISTS_NOMINAL="false"
EXISTS_INTERLOCK="false"
EXISTS_RECOVERY="false"
EXISTS_CSV="false"

[ -f "/home/ga/test_step_1_nominal.png" ] && EXISTS_NOMINAL="true"
[ -f "/home/ga/test_step_2_interlock.png" ] && EXISTS_INTERLOCK="true"
[ -f "/home/ga/test_step_3_recovery.png" ] && EXISTS_RECOVERY="true"
[ -f "/home/ga/Desktop/fvp_results.csv" ] && EXISTS_CSV="true"

# 2. Read CSV Content (if exists)
CSV_CONTENT=""
if [ "$EXISTS_CSV" = "true" ]; then
    # Read file, escape double quotes, replace newlines with \n
    CSV_CONTENT=$(cat /home/ga/Desktop/fvp_results.csv | sed 's/"/\\"/g' | awk '{printf "%s\\n", $0}')
fi

# 3. Analyze Logs for Device Creation & Interaction
LOG_FILE="/home/ga/openice/logs/openice.log"
INITIAL_LOG_SIZE=$(cat /tmp/initial_log_size 2>/dev/null || echo "0")
NEW_LOG=$(tail -c +$((INITIAL_LOG_SIZE + 1)) "$LOG_FILE" 2>/dev/null || echo "")

# Check for Pulse Oximeter creation
LOG_PULSE_OX="false"
if echo "$NEW_LOG" | grep -qiE "Pulse.*Oximeter|SpO2|Nonin|Masimo"; then
    LOG_PULSE_OX="true"
fi

# Check for Infusion Pump creation
LOG_PUMP="false"
if echo "$NEW_LOG" | grep -qiE "Infusion.*Pump|Pump.*Sim|Alaris|QCore"; then
    LOG_PUMP="true"
fi

# Check for Infusion Safety App launch
LOG_SAFETY_APP="false"
if echo "$NEW_LOG" | grep -qiE "Infusion.*Safety|Safety.*Interlock|Objective.*Safety"; then
    LOG_SAFETY_APP="true"
fi

# 4. Check OpenICE Status
OPENICE_RUNNING="false"
if is_openice_running; then
    OPENICE_RUNNING="true"
fi

# Create result JSON
create_result_json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "artifacts": {
        "nominal_png_exists": $EXISTS_NOMINAL,
        "interlock_png_exists": $EXISTS_INTERLOCK,
        "recovery_png_exists": $EXISTS_RECOVERY,
        "csv_exists": $EXISTS_CSV
    },
    "csv_content": "$CSV_CONTENT",
    "logs": {
        "pulse_ox_created": $LOG_PULSE_OX,
        "pump_created": $LOG_PUMP,
        "safety_app_launched": $LOG_SAFETY_APP
    },
    "openice_running": $OPENICE_RUNNING,
    "screenshot_path": "/tmp/task_final_screenshot.png"
}
EOF

echo "=== Export Complete ==="
cat /tmp/task_result.json