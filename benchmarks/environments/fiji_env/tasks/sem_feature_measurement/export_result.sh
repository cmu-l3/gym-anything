#!/bin/bash
echo "=== Exporting SEM Task Results ==="

# 1. Snapshot final state
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Collect timestamps and file info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
NOW=$(date +%s)

RES_DIR="/home/ga/Fiji_Data/results/sem"
IMG_PATH="$RES_DIR/annotated_sem.png"
CSV_PATH="$RES_DIR/grain_measurements.csv"
TXT_PATH="$RES_DIR/measurement_summary.txt"

# Helper to get file info
get_file_info() {
    local f="$1"
    if [ -f "$f" ]; then
        local size=$(stat -c%s "$f")
        local mtime=$(stat -c%Y "$f")
        echo "{\"exists\": true, \"size\": $size, \"mtime\": $mtime}"
    else
        echo "{\"exists\": false}"
    fi
}

IMG_INFO=$(get_file_info "$IMG_PATH")
CSV_INFO=$(get_file_info "$CSV_PATH")
TXT_INFO=$(get_file_info "$TXT_PATH")

# 3. Create JSON payload
# We don't read the file contents here; we let the verifier pull the files.
# We just provide metadata and the screenshot path.

cat > /tmp/task_result.json <<EOF
{
  "task_start_time": $TASK_START,
  "export_time": $NOW,
  "annotated_image": $IMG_INFO,
  "measurements_csv": $CSV_INFO,
  "summary_report": $TXT_INFO,
  "final_screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure readable
chmod 644 /tmp/task_result.json

echo "Export complete. JSON saved to /tmp/task_result.json"