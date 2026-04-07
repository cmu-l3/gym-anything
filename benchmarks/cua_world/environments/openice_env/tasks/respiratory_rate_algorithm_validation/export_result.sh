#!/bin/bash
echo "=== Exporting Respiratory Rate Algorithm Validation Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# --- Timestamps ---
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# --- Window Analysis ---
INITIAL_WINDOWS=$(cat /tmp/initial_window_count 2>/dev/null || echo "0")
FINAL_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | wc -l)
WINDOW_INCREASE=$((FINAL_WINDOWS - INITIAL_WINDOWS))
CURRENT_WINDOW_LIST=$(DISPLAY=:1 wmctrl -l 2>/dev/null)

# --- Log Analysis ---
LOG_FILE="/home/ga/openice/logs/openice.log"
INITIAL_LOG_SIZE=$(cat /tmp/initial_log_size 2>/dev/null || echo "0")
# Get only new lines generated during the task
NEW_LOG=$(tail -c +$((INITIAL_LOG_SIZE + 1)) "$LOG_FILE" 2>/dev/null || echo "")

# --- Device Detection (Capnograph specific) ---
# Check for creation of Capnograph/Capnometer in logs or window titles
CAPNOGRAPH_CREATED="false"
if echo "$NEW_LOG" | grep -qiE "Capnograph|Capnometer|SimulatedCapno"; then
    CAPNOGRAPH_CREATED="true"
fi
if echo "$CURRENT_WINDOW_LIST" | grep -qiE "Capnograph|Capnometer"; then
    CAPNOGRAPH_CREATED="true"
fi

# Check for WRONG device types (common mistake)
MULTIPARAM_CREATED="false"
if echo "$NEW_LOG" | grep -qiE "Multiparameter|MultiParam"; then
    MULTIPARAM_CREATED="true"
fi

# --- App Detection (Respiratory Rate Calculator) ---
APP_LAUNCHED="false"
if echo "$NEW_LOG" | grep -qiE "RespiratoryRate|RespRateCalc|RRCalc"; then
    APP_LAUNCHED="true"
fi
if echo "$CURRENT_WINDOW_LIST" | grep -qiE "Respiratory.*Rate|Resp.*Rate"; then
    APP_LAUNCHED="true"
fi

# --- Report File Analysis ---
REPORT_PATH="/home/ga/Desktop/rr_validation_report.txt"
REPORT_EXISTS="false"
REPORT_SIZE=0
REPORT_MTIME=0
REPORT_CONTENT=""
REPORT_HAS_NUMBERS="false"
REPORT_HAS_KEYWORDS="false"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    
    # Read content (limited size)
    REPORT_CONTENT=$(head -c 1000 "$REPORT_PATH")
    
    # Check for numbers (RR values)
    if echo "$REPORT_CONTENT" | grep -qE "[0-9]+"; then
        REPORT_HAS_NUMBERS="true"
    fi
    
    # Check for keywords
    if echo "$REPORT_CONTENT" | grep -qiE "match|equal|same|confirm|valid|source|calc|derived"; then
        REPORT_HAS_KEYWORDS="true"
    fi
fi

# --- OpenICE Status ---
OPENICE_RUNNING="false"
if is_openice_running; then
    OPENICE_RUNNING="true"
fi

# --- Create JSON Result ---
create_result_json << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "openice_running": $OPENICE_RUNNING,
    "capnograph_created": $CAPNOGRAPH_CREATED,
    "multiparam_created": $MULTIPARAM_CREATED,
    "app_launched": $APP_LAUNCHED,
    "window_increase": $WINDOW_INCREASE,
    "report_exists": $REPORT_EXISTS,
    "report_size": $REPORT_SIZE,
    "report_mtime": $REPORT_MTIME,
    "report_has_numbers": $REPORT_HAS_NUMBERS,
    "report_has_keywords": $REPORT_HAS_KEYWORDS,
    "screenshot_path": "/tmp/task_final_screenshot.png"
}
EOF

echo "=== Export Complete ==="
echo "Capnograph: $CAPNOGRAPH_CREATED | App: $APP_LAUNCHED | Report: $REPORT_EXISTS"
cat /tmp/task_result.json