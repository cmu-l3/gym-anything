#!/bin/bash
echo "=== Exporting Generate Asset Flood Timeline Result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 2. Paths
OUTPUT_CSV="/home/ga/Documents/hec_ras_results/flood_timeline.csv"
GROUND_TRUTH_JSON="/var/lib/hec_ras/ground_truth.json"
RESULT_JSON="/tmp/task_result.json"

# 3. Check for output file
OUTPUT_EXISTS="false"
OUTPUT_SIZE="0"
if [ -f "$OUTPUT_CSV" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_CSV" 2>/dev/null || echo "0")
fi

# 4. Check for ground truth
GT_EXISTS="false"
if [ -f "$GROUND_TRUTH_JSON" ]; then
    GT_EXISTS="true"
    # Copy ground truth to a temp location readable by the export process
    cp "$GROUND_TRUTH_JSON" /tmp/ground_truth.json
    chmod 644 /tmp/ground_truth.json
fi

# 5. Create result JSON wrapper
# We will embed the CSV content directly if it's small enough, or just reference it.
# For verification simplicity, let's copy the CSV content to a temp file that the verifier can read.

if [ "$OUTPUT_EXISTS" = "true" ]; then
    cp "$OUTPUT_CSV" /tmp/agent_output.csv
    chmod 644 /tmp/agent_output.csv
fi

# 6. Capture file timestamps for anti-gaming
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILE_MTIME="0"
if [ "$OUTPUT_EXISTS" = "true" ]; then
    FILE_MTIME=$(stat -c %Y "$OUTPUT_CSV" 2>/dev/null || echo "0")
fi

# 7. Create metadata JSON
cat > "$RESULT_JSON" << EOF
{
    "output_exists": $OUTPUT_EXISTS,
    "ground_truth_exists": $GT_EXISTS,
    "task_start_time": $TASK_START,
    "file_mtime": $FILE_MTIME,
    "output_csv_path": "/tmp/agent_output.csv",
    "ground_truth_path": "/tmp/ground_truth.json",
    "screenshot_path": "/tmp/task_end_screenshot.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Ensure permissions
chmod 644 "$RESULT_JSON"

echo "Result exported to $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export Complete ==="