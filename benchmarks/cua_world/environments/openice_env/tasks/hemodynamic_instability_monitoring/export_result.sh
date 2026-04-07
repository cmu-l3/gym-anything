#!/bin/bash
echo "=== Exporting Hemodynamic Instability Monitoring Result ==="

source /workspace/scripts/task_utils.sh

# Capture final state screenshot
take_screenshot /tmp/task_final_screenshot.png

# Get timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Get window counts
INITIAL_WINDOWS=$(cat /tmp/initial_window_count 2>/dev/null || echo "0")
FINAL_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | wc -l)
WINDOW_INCREASE=$((FINAL_WINDOWS - INITIAL_WINDOWS))

# Log Analysis
LOG_FILE="/home/ga/openice/logs/openice.log"
INITIAL_LOG_SIZE=$(cat /tmp/initial_log_size 2>/dev/null || echo "0")
NEW_LOG=$(tail -c +$((INITIAL_LOG_SIZE + 1)) "$LOG_FILE" 2>/dev/null || echo "")

# Check for OpenICE running
OPENICE_RUNNING="false"
if is_openice_running; then
    OPENICE_RUNNING="true"
fi

# 1. Check for specific device creations in logs
MULTIPARAM_CREATED="false"
if echo "$NEW_LOG" | grep -qiE "Multiparameter|MultiParam|SimulatedDevice.*Metric"; then
    MULTIPARAM_CREATED="true"
fi

NIBP_CREATED="false"
if echo "$NEW_LOG" | grep -qiE "NIBP|NonInvasive|BloodPressure"; then
    NIBP_CREATED="true"
fi

PUMP_CREATED="false"
if echo "$NEW_LOG" | grep -qiE "Infusion|Pump|IcePump"; then
    PUMP_CREATED="true"
fi

# 2. Check for App Launch
APP_LAUNCHED="false"
if echo "$NEW_LOG" | grep -qiE "VitalSigns|Vital Signs|ClinicalApp"; then
    APP_LAUNCHED="true"
fi
# Fallback check using window titles
if DISPLAY=:1 wmctrl -l | grep -qi "Vital"; then
    APP_LAUNCHED="true"
fi

# 3. Check for Status Note
NOTE_FILE="/home/ga/Desktop/shock_protocol_status.txt"
NOTE_EXISTS="false"
NOTE_CONTENT=""
NOTE_MTIME=0

if [ -f "$NOTE_FILE" ]; then
    NOTE_EXISTS="true"
    NOTE_CONTENT=$(cat "$NOTE_FILE" | head -c 1000) # Read first 1000 chars
    NOTE_MTIME=$(stat -c %Y "$NOTE_FILE")
fi

# 4. Check for Simulated Values in Logs (Optimistic check)
# Sometimes OpenICE logs parameter updates if log level is high enough
LOG_HAS_110="false"
LOG_HAS_90="false"
if echo "$NEW_LOG" | grep -q "110"; then LOG_HAS_110="true"; fi
if echo "$NEW_LOG" | grep -q "90"; then LOG_HAS_90="true"; fi

# Create JSON result
create_result_json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "openice_running": $OPENICE_RUNNING,
    "multiparam_created": $MULTIPARAM_CREATED,
    "nibp_created": $NIBP_CREATED,
    "pump_created": $PUMP_CREATED,
    "app_launched": $APP_LAUNCHED,
    "window_increase": $WINDOW_INCREASE,
    "note_exists": $NOTE_EXISTS,
    "note_mtime": $NOTE_MTIME,
    "note_content": "$(escape_json_value "$NOTE_CONTENT")",
    "log_has_110": $LOG_HAS_110,
    "log_has_90": $LOG_HAS_90,
    "screenshot_path": "/tmp/task_final_screenshot.png"
}
EOF

echo "=== Export Complete ==="
cat /tmp/task_result.json