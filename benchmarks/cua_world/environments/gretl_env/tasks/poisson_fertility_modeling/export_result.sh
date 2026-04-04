#!/bin/bash
echo "=== Exporting Poisson Task Results ==="

source /workspace/scripts/task_utils.sh

# Paths
RESULTS_FILE="/home/ga/Documents/gretl_output/poisson_results.txt"
FITTED_FILE="/home/ga/Documents/gretl_output/poisson_fitted.csv"
TEST_FILE="/home/ga/Documents/gretl_output/dispersion_test.txt"

# Timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
NOW=$(date +%s)

# Helper to check file status
check_file() {
    local fpath="$1"
    if [ -f "$fpath" ]; then
        local mtime=$(stat -c %Y "$fpath" 2>/dev/null || echo "0")
        local size=$(stat -c %s "$fpath" 2>/dev/null || echo "0")
        if [ "$mtime" -ge "$TASK_START" ]; then
            echo "{\"exists\": true, \"created_during_task\": true, \"size\": $size, \"path\": \"$fpath\"}"
        else
            echo "{\"exists\": true, \"created_during_task\": false, \"size\": $size, \"path\": \"$fpath\"}"
        fi
    else
        echo "{\"exists\": false, \"created_during_task\": false, \"size\": 0, \"path\": \"$fpath\"}"
    fi
}

# Capture Final State
take_screenshot /tmp/task_final.png

# Check if Gretl is still running
APP_RUNNING=$(pgrep -f "gretl" > /dev/null && echo "true" || echo "false")

# Build JSON Result
# We use a temp file to avoid permission issues during creation
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $NOW,
    "app_was_running": $APP_RUNNING,
    "files": {
        "results": $(check_file "$RESULTS_FILE"),
        "fitted": $(check_file "$FITTED_FILE"),
        "test": $(check_file "$TEST_FILE")
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
chmod 644 "$TEMP_JSON"
mv "$TEMP_JSON" /tmp/task_result.json

# Copy output files to /tmp so the verifier can easily grab them using copy_from_env
# (The verifier might not have access to /home/ga directly if permissions assume strict isolation, 
# though copy_from_env usually runs as root. Doing this is a safety net.)
[ -f "$RESULTS_FILE" ] && cp "$RESULTS_FILE" /tmp/poisson_results.txt && chmod 644 /tmp/poisson_results.txt
[ -f "$FITTED_FILE" ] && cp "$FITTED_FILE" /tmp/poisson_fitted.csv && chmod 644 /tmp/poisson_fitted.csv
[ -f "$TEST_FILE" ] && cp "$TEST_FILE" /tmp/dispersion_test.txt && chmod 644 /tmp/dispersion_test.txt

echo "Export complete. Result JSON:"
cat /tmp/task_result.json