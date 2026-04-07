#!/bin/bash
echo "=== Exporting CCHD Screening Configuration result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot (system capture)
take_screenshot /tmp/task_final_screenshot.png

# Get Timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# --- File Evidence Collection ---
REPORT_PATH="/home/ga/Desktop/cchd_device_map.txt"
EVIDENCE_IMG_PATH="/home/ga/Desktop/cchd_screen_evidence.png"

REPORT_EXISTS="false"
REPORT_CONTENT=""
REPORT_MTIME=0

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    # Read content, escape quotes/newlines for JSON
    REPORT_CONTENT=$(cat "$REPORT_PATH" | tr '\n' ' ' | sed 's/"/\\"/g')
fi

EVIDENCE_IMG_EXISTS="false"
if [ -f "$EVIDENCE_IMG_PATH" ]; then
    EVIDENCE_IMG_EXISTS="true"
fi

# --- Window State Analysis ---
INITIAL_WINDOWS=$(cat /tmp/initial_window_count 2>/dev/null || echo "0")
FINAL_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | wc -l)
WINDOW_INCREASE=$((FINAL_WINDOWS - INITIAL_WINDOWS))

# Get list of open windows to check for "Pulse Oximeter" or "Device"
WINDOW_LIST=$(DISPLAY=:1 wmctrl -l 2>/dev/null | sed 's/"/\\"/g' | tr '\n' '|')

# --- Log Analysis ---
# We need to find evidence of TWO devices being created and setting values 98 and 90.
LOG_FILE="/home/ga/openice/logs/openice.log"
INITIAL_LOG_SIZE=$(cat /tmp/initial_log_size 2>/dev/null || echo "0")

# Extract new log lines (limit to last 2000 lines to avoid massive JSON)
NEW_LOG=$(tail -c +$((INITIAL_LOG_SIZE + 1)) "$LOG_FILE" 2>/dev/null | tail -n 2000)

# Check for specific values in logs (simple grep check for scoring hints)
FOUND_98=$(echo "$NEW_LOG" | grep -c "98" || echo "0")
FOUND_90=$(echo "$NEW_LOG" | grep -c "90" || echo "0")
FOUND_PULSE_OX=$(echo "$NEW_LOG" | grep -ic "Pulse.*Ox" || echo "0")

# Encode Log snippet for Verifier (careful with size/escaping)
# We filter the log to lines that might contain UDI or numeric data to save space
# Pattern: looks for UUID-like strings, "98", "90", or "Pulse"
RELEVANT_LOGS=$(echo "$NEW_LOG" | grep -E "98|90|Pulse|Oximeter|[0-9a-fA-F]{8}-" | tail -n 100 | tr '\n' ' ' | sed 's/"/\\"/g')

# --- Check OpenICE Status ---
OPENICE_RUNNING="false"
if is_openice_running; then
    OPENICE_RUNNING="true"
fi

# --- Create JSON ---
create_result_json << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "openice_running": $OPENICE_RUNNING,
    "initial_window_count": $INITIAL_WINDOWS,
    "final_window_count": $FINAL_WINDOWS,
    "window_list": "$WINDOW_LIST",
    "report_exists": $REPORT_EXISTS,
    "report_content": "$REPORT_CONTENT",
    "report_mtime": $REPORT_MTIME,
    "evidence_screenshot_exists": $EVIDENCE_IMG_EXISTS,
    "log_hints": {
        "found_98": $FOUND_98,
        "found_90": $FOUND_90,
        "found_pulse_ox": $FOUND_PULSE_OX
    },
    "relevant_logs": "$RELEVANT_LOGS",
    "system_screenshot_path": "/tmp/task_final_screenshot.png"
}
EOF

echo "=== Export Complete ==="
cat /tmp/task_result.json