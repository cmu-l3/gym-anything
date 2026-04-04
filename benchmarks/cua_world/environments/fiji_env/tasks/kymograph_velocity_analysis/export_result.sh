#!/bin/bash
echo "=== Exporting Kymograph Analysis Results ==="

RESULTS_DIR="/home/ga/Fiji_Data/results/kymograph"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
NOW=$(date +%s)

# 1. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check output files
KYMO_IMG="$RESULTS_DIR/kymograph_main.png"
CSV_FILE="$RESULTS_DIR/velocity_measurements.csv"
REPORT_FILE="$RESULTS_DIR/kymograph_report.txt"

# Helper to check file status
check_file() {
    local f="$1"
    if [ -f "$f" ]; then
        local mtime=$(stat -c %Y "$f")
        local size=$(stat -c %s "$f")
        if [ "$mtime" -ge "$TASK_START" ]; then
            echo "{\"exists\": true, \"valid_time\": true, \"size\": $size, \"path\": \"$f\"}"
        else
            echo "{\"exists\": true, \"valid_time\": false, \"size\": $size, \"path\": \"$f\"}"
        fi
    else
        echo "{\"exists\": false, \"valid_time\": false, \"size\": 0, \"path\": \"\"}"
    fi
}

KYMO_STATUS=$(check_file "$KYMO_IMG")
CSV_STATUS=$(check_file "$CSV_FILE")
REPORT_STATUS=$(check_file "$REPORT_FILE")

# 3. Create JSON summary
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $NOW,
    "kymograph_image": $KYMO_STATUS,
    "velocity_csv": $CSV_STATUS,
    "report_text": $REPORT_STATUS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 4. Copy specific files to temp for the verifier to access easily via copy_from_env
# (The verifier uses copy_from_env on specific paths, so we ensure they are readable)
if [ -f "$CSV_FILE" ]; then
    cp "$CSV_FILE" /tmp/velocity_measurements.csv
    chmod 644 /tmp/velocity_measurements.csv
fi

if [ -f "$REPORT_FILE" ]; then
    cp "$REPORT_FILE" /tmp/kymograph_report.txt
    chmod 644 /tmp/kymograph_report.txt
fi

if [ -f "$KYMO_IMG" ]; then
    cp "$KYMO_IMG" /tmp/kymograph_main.png
    chmod 644 /tmp/kymograph_main.png
fi

# Ensure the main result json is readable
chmod 644 /tmp/task_result.json

echo "Export complete. Result JSON:"
cat /tmp/task_result.json