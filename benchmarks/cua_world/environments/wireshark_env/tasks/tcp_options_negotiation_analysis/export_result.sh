#!/bin/bash
set -e
echo "=== Exporting TCP Options Negotiation Analysis Results ==="

# Define paths
CSV_OUTPUT="/home/ga/Documents/tcp_options_report.csv"
SUMMARY_OUTPUT="/home/ga/Documents/tcp_options_summary.txt"
TASK_START_FILE="/tmp/task_start_time.txt"
TASK_START=$(cat "$TASK_START_FILE" 2>/dev/null || echo "0")

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# ------------------------------------------------------------------
# CHECK FILES
# ------------------------------------------------------------------

check_file() {
    local fpath="$1"
    if [ -f "$fpath" ]; then
        local mtime=$(stat -c %Y "$fpath" 2>/dev/null || echo "0")
        if [ "$mtime" -ge "$TASK_START" ]; then
            echo "true"
        else
            echo "stale"
        fi
    else
        echo "false"
    fi
}

CSV_STATUS=$(check_file "$CSV_OUTPUT")
SUMMARY_STATUS=$(check_file "$SUMMARY_OUTPUT")
APP_RUNNING=$(pgrep -f "wireshark" > /dev/null && echo "true" || echo "false")

echo "CSV Status: $CSV_STATUS"
echo "Summary Status: $SUMMARY_STATUS"

# ------------------------------------------------------------------
# CREATE RESULT JSON
# ------------------------------------------------------------------
# We don't parse the full CSV here (too complex for bash). 
# We export metadata. The verifier will copy the actual files.

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $(date +%s),
    "csv_exists": "$CSV_STATUS",
    "summary_exists": "$SUMMARY_STATUS",
    "app_was_running": $APP_RUNNING,
    "csv_path": "$CSV_OUTPUT",
    "summary_path": "$SUMMARY_OUTPUT",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result metadata saved to /tmp/task_result.json"
echo "=== Export complete ==="