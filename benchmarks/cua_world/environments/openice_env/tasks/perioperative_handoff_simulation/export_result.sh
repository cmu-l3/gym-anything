#!/bin/bash
echo "=== Exporting Perioperative Device Handoff Result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final state
take_screenshot /tmp/task_final.png

# 2. Get timing data
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Analyze Logs (New entries only)
LOG_FILE="/home/ga/openice/logs/openice.log"
INITIAL_LOG_SIZE=$(cat /tmp/initial_log_size.txt 2>/dev/null || echo "0")
NEW_LOGS=""

if [ -f "$LOG_FILE" ]; then
    # Get only the lines appended since task start
    NEW_LOGS=$(tail -c +$((INITIAL_LOG_SIZE + 1)) "$LOG_FILE" 2>/dev/null)
fi

# 4. Analyze Windows
INITIAL_WINDOWS_CONTENT=$(cat /tmp/initial_windows.txt 2>/dev/null || echo "")
CURRENT_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null)
# Count how many new windows were created (proxy for device creation)
INITIAL_COUNT=$(echo "$INITIAL_WINDOWS_CONTENT" | wc -l)
FINAL_COUNT=$(echo "$CURRENT_WINDOWS" | wc -l)
NEW_WINDOW_COUNT=$((FINAL_COUNT - INITIAL_COUNT))

# 5. Check for Specific Devices (in Logs OR Windows)
# Helper function to check presence
check_device() {
    local pattern="$1"
    if echo "$NEW_LOGS" | grep -qiE "$pattern"; then
        echo "true"
        return
    fi
    if echo "$CURRENT_WINDOWS" | grep -qiE "$pattern"; then
        echo "true"
        return
    fi
    echo "false"
}

# Pre-Op Devices
HAS_PULSE_OX=$(check_device "pulse.?ox|spo2.*sim|pulse.*oximeter")
HAS_NIBP=$(check_device "nibp|noninvasive.*blood|blood.*pressure")

# OR Devices
HAS_MULTIPARAM=$(check_device "multiparameter|multi.?param|patient.*monitor")
HAS_CAPNO=$(check_device "capno|co2|etco2|carbon.*dioxide")
HAS_PUMP=$(check_device "infusion|pump|infusionpump")

# Clinical App
HAS_VITAL_SIGNS=$(check_device "vital.?sign|vital.*app|clinical.*app")

# 6. Analyze Checklist File
CHECKLIST_PATH="/home/ga/Desktop/periop_handoff_checklist.txt"
FILE_EXISTS="false"
FILE_SIZE="0"
FILE_MTIME="0"
CONTENT_PHASES="false"
CONTENT_PARAMS="false"
CONTENT_TRANSITION="false"
CONTENT_RAW=""

if [ -f "$CHECKLIST_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$CHECKLIST_PATH")
    FILE_MTIME=$(stat -c %Y "$CHECKLIST_PATH")
    
    # Read content for verification (safe length limit)
    CONTENT_RAW=$(head -c 2000 "$CHECKLIST_PATH")
    
    # Check for phases (Pre-Op and OR mentioned)
    if echo "$CONTENT_RAW" | grep -qiE "pre.?op|pre.?operative" && \
       echo "$CONTENT_RAW" | grep -qiE "operating.?room|intra.?op|OR.*monitor"; then
        CONTENT_PHASES="true"
    fi
    
    # Check for physiological parameters (count matches)
    PARAM_MATCHES=$(echo "$CONTENT_RAW" | grep -ioE "spo2|heart|rate|pulse|bp|blood|pressure|ecg|co2|etco2|temp|infusion" | sort -u | wc -l)
    if [ "$PARAM_MATCHES" -ge 4 ]; then
        CONTENT_PARAMS="true"
    fi
    
    # Check for transition language
    if echo "$CONTENT_RAW" | grep -qiE "replace|supplement|upgrade|transition|handoff|transfer|move|change"; then
        CONTENT_TRANSITION="true"
    fi
fi

# 7. Construct Result JSON
# Use a temp file to avoid permission issues during write
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "new_window_count": $NEW_WINDOW_COUNT,
    "devices": {
        "pulse_ox": $HAS_PULSE_OX,
        "nibp": $HAS_NIBP,
        "multiparameter": $HAS_MULTIPARAM,
        "capno": $HAS_CAPNO,
        "pump": $HAS_PUMP
    },
    "app_launched": $HAS_VITAL_SIGNS,
    "checklist": {
        "exists": $FILE_EXISTS,
        "size_bytes": $FILE_SIZE,
        "mtime": $FILE_MTIME,
        "has_phases": $CONTENT_PHASES,
        "has_params": $CONTENT_PARAMS,
        "has_transition": $CONTENT_TRANSITION
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="
cat /tmp/task_result.json