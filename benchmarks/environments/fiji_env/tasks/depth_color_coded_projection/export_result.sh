#!/bin/bash
echo "=== Exporting Depth Color-Coded Projection Results ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

RESULTS_DIR="/home/ga/Fiji_Data/results/depth_projection"
MIP_PATH="$RESULTS_DIR/standard_mip.png"
CODED_PATH="$RESULTS_DIR/depth_coded_projection.png"
REPORT_PATH="$RESULTS_DIR/stack_report.txt"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Helper function to check file
check_file() {
    local fpath="$1"
    if [ -f "$fpath" ]; then
        local size=$(stat -c%s "$fpath")
        local mtime=$(stat -c%Y "$fpath")
        local created_during="false"
        if [ "$mtime" -gt "$TASK_START" ]; then
            created_during="true"
        fi
        echo "\"exists\": true, \"size\": $size, \"created_during\": $created_during"
    else
        echo "\"exists\": false, \"size\": 0, \"created_during\": false"
    fi
}

# Generate JSON result
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "mip_file": { $(check_file "$MIP_PATH") },
    "coded_file": { $(check_file "$CODED_PATH") },
    "report_file": { $(check_file "$REPORT_PATH") },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Copy output files to temp for verification (to avoid permission issues reading user home)
cp "$MIP_PATH" /tmp/verify_mip.png 2>/dev/null || true
cp "$CODED_PATH" /tmp/verify_coded.png 2>/dev/null || true
cp "$REPORT_PATH" /tmp/verify_report.txt 2>/dev/null || true
chmod 644 /tmp/verify_* 2>/dev/null || true
chmod 644 /tmp/task_result.json

echo "Export complete. Result JSON:"
cat /tmp/task_result.json