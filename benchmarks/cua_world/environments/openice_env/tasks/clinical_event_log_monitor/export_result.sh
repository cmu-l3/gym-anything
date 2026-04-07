#!/bin/bash
echo "=== Exporting clinical_event_log_monitor result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# --- DATA COLLECTION ---

# 1. Timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 2. Log Analysis (New lines only)
LOG_FILE="/home/ga/openice/logs/openice.log"
INITIAL_LOG_SIZE=$(cat /tmp/initial_log_size 2>/dev/null || echo "0")
# Get content added during task
NEW_LOG_CONTENT=$(tail -c +$((INITIAL_LOG_SIZE + 1)) "$LOG_FILE" 2>/dev/null || echo "")

# Check for device keywords in new logs
LOG_HAS_DEVICE_1="false"
LOG_HAS_DEVICE_2="false"

# Count unique device identifiers in log (heuristic)
# Look for "Created DeviceAdapter" or similar common patterns in OpenICE logs
# Or simply look for distinct device type names
if echo "$NEW_LOG_CONTENT" | grep -qiE "Multiparameter|Monitor"; then
    LOG_HAS_DEVICE_1="true"
fi
if echo "$NEW_LOG_CONTENT" | grep -qiE "Pulse|Oximeter|Pump|Infusion|Capno|CO2"; then
    LOG_HAS_DEVICE_2="true"
fi

# 3. Window Analysis
INITIAL_WINDOWS=$(cat /tmp/initial_window_count 2>/dev/null || echo "0")
FINAL_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | wc -l)
WINDOW_INCREASE=$((FINAL_WINDOWS - INITIAL_WINDOWS))

# Check specific window titles
WINDOW_TITLES=$(DISPLAY=:1 wmctrl -l 2>/dev/null)
WINDOW_HAS_DEVICE_1="false"
WINDOW_HAS_DEVICE_2="false"

if echo "$WINDOW_TITLES" | grep -qiE "Multiparameter|Monitor"; then
    WINDOW_HAS_DEVICE_1="true"
fi
if echo "$WINDOW_TITLES" | grep -qiE "Pulse|Oximeter|Pump|Infusion|Capno|CO2"; then
    WINDOW_HAS_DEVICE_2="true"
fi

# 4. Script Verification
SCRIPT_PATH="/home/ga/Desktop/event_monitor.sh"
SCRIPT_EXISTS="false"
SCRIPT_EXECUTABLE="false"
SCRIPT_SIZE=0
SCRIPT_HAS_SHEBANG="false"
SCRIPT_HAS_LOGPATH="false"
SCRIPT_HAS_COMMANDS="false"

if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_EXISTS="true"
    SCRIPT_SIZE=$(stat -c %s "$SCRIPT_PATH" 2>/dev/null || echo "0")
    if [ -x "$SCRIPT_PATH" ]; then
        SCRIPT_EXECUTABLE="true"
    fi
    if head -n 1 "$SCRIPT_PATH" | grep -q "^#!"; then
        SCRIPT_HAS_SHEBANG="true"
    fi
    if grep -q "/home/ga/openice/logs/openice.log" "$SCRIPT_PATH"; then
        SCRIPT_HAS_LOGPATH="true"
    fi
    # Check for common parsing commands
    if grep -E "grep|awk|sed|wc|tail|cut" "$SCRIPT_PATH" > /dev/null; then
        SCRIPT_HAS_COMMANDS="true"
    fi
fi

# 5. Output File Verification
OUTPUT_PATH="/home/ga/Desktop/event_summary.txt"
OUTPUT_EXISTS="false"
OUTPUT_SIZE=0
OUTPUT_HAS_NUMBERS="false"
OUTPUT_MTIME=0

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if grep -E "[0-9]" "$OUTPUT_PATH" > /dev/null; then
        OUTPUT_HAS_NUMBERS="true"
    fi
fi

# 6. Documentation Verification
DOC_PATH="/home/ga/Desktop/log_format_doc.txt"
DOC_EXISTS="false"
DOC_SIZE=0
DOC_HAS_KEYWORDS="false"
DOC_HAS_RECOMMENDATION="false"
DOC_MTIME=0

if [ -f "$DOC_PATH" ]; then
    DOC_EXISTS="true"
    DOC_SIZE=$(stat -c %s "$DOC_PATH" 2>/dev/null || echo "0")
    DOC_MTIME=$(stat -c %Y "$DOC_PATH" 2>/dev/null || echo "0")
    
    # Check for structure keywords
    if grep -iE "timestamp|level|INFO|WARN|ERROR|class|logger|message" "$DOC_PATH" > /dev/null; then
        DOC_HAS_KEYWORDS="true"
    fi
    
    # Check for recommendation keywords
    if grep -iE "recommend|monitor|alert|detect|critical" "$DOC_PATH" > /dev/null; then
        DOC_HAS_RECOMMENDATION="true"
    fi
fi

# --- JSON GENERATION ---

create_result_json << EOF
{
    "task_start": $TASK_START,
    "log_has_device_1": $LOG_HAS_DEVICE_1,
    "log_has_device_2": $LOG_HAS_DEVICE_2,
    "window_increase": $WINDOW_INCREASE,
    "window_has_device_1": $WINDOW_HAS_DEVICE_1,
    "window_has_device_2": $WINDOW_HAS_DEVICE_2,
    "script": {
        "exists": $SCRIPT_EXISTS,
        "executable": $SCRIPT_EXECUTABLE,
        "size": $SCRIPT_SIZE,
        "has_shebang": $SCRIPT_HAS_SHEBANG,
        "has_logpath": $SCRIPT_HAS_LOGPATH,
        "has_commands": $SCRIPT_HAS_COMMANDS
    },
    "output": {
        "exists": $OUTPUT_EXISTS,
        "size": $OUTPUT_SIZE,
        "has_numbers": $OUTPUT_HAS_NUMBERS,
        "mtime": $OUTPUT_MTIME
    },
    "doc": {
        "exists": $DOC_EXISTS,
        "size": $DOC_SIZE,
        "has_keywords": $DOC_HAS_KEYWORDS,
        "has_recommendation": $DOC_HAS_RECOMMENDATION,
        "mtime": $DOC_MTIME
    },
    "screenshot_path": "/tmp/task_final_screenshot.png"
}
EOF

echo "=== Export Complete ==="
cat /tmp/task_result.json