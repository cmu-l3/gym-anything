#!/bin/bash
echo "=== Exporting compute_momentum_flux results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

RESULTS_DIR="/home/ga/Documents/hec_ras_results"
SCRIPT_PATH="$RESULTS_DIR/compute_momentum_flux.py"
CSV_PATH="$RESULTS_DIR/momentum_flux.csv"
REPORT_PATH="$RESULTS_DIR/momentum_summary.txt"

# Helper to check file status
check_file() {
    local fpath="$1"
    if [ -f "$fpath" ]; then
        local mtime=$(stat -c %Y "$fpath" 2>/dev/null || echo "0")
        if [ "$mtime" -gt "$TASK_START" ]; then
            echo "created_during_task"
        else
            echo "pre_existing"
        fi
    else
        echo "missing"
    fi
}

# Check all required files
SCRIPT_STATUS=$(check_file "$SCRIPT_PATH")
CSV_STATUS=$(check_file "$CSV_PATH")
REPORT_STATUS=$(check_file "$REPORT_PATH")

echo "File Status:"
echo "Script: $SCRIPT_STATUS"
echo "CSV: $CSV_STATUS"
echo "Report: $REPORT_STATUS"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Prepare files for export (copy to /tmp with known names for verifier)
# We handle permissions to ensure the host can read them
cp "$CSV_PATH" /tmp/export_momentum_flux.csv 2>/dev/null || true
cp "$REPORT_PATH" /tmp/export_momentum_summary.txt 2>/dev/null || true
cp "$SCRIPT_PATH" /tmp/export_compute_script.py 2>/dev/null || true
chmod 644 /tmp/export_* 2>/dev/null || true

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "script_status": "$SCRIPT_STATUS",
    "csv_status": "$CSV_STATUS",
    "report_status": "$REPORT_STATUS",
    "script_path": "$SCRIPT_PATH",
    "csv_path": "$CSV_PATH",
    "report_path": "$REPORT_PATH",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move JSON to final location
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "=== Export complete ==="