#!/bin/bash
# Export script for Boolean Overlap Analysis task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting Boolean Overlap Results ==="

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Define expected paths
RESULTS_DIR="/home/ga/ImageJ_Data/results"
FILE_RED="$RESULTS_DIR/mask_red.tif"
FILE_GREEN="$RESULTS_DIR/mask_green.tif"
FILE_OVERLAP="$RESULTS_DIR/mask_overlap.tif"
FILE_COUNTS="$RESULTS_DIR/overlap_counts.csv"
TASK_START_FILE="/tmp/task_start_timestamp"

# 3. Helper to get file info
get_file_info() {
    local fpath="$1"
    if [ -f "$fpath" ]; then
        local size=$(stat -c %s "$fpath")
        local mtime=$(stat -c %Y "$fpath")
        echo "{\"exists\": true, \"size\": $size, \"mtime\": $mtime, \"path\": \"$fpath\"}"
    else
        echo "{\"exists\": false, \"size\": 0, \"mtime\": 0, \"path\": \"$fpath\"}"
    fi
}

# 4. Generate JSON summary of file status
# We do not read the images here; the verifier will copy them out
TASK_START=$(cat "$TASK_START_FILE" 2>/dev/null || echo "0")

cat > /tmp/boolean_overlap_result.json <<EOF
{
    "task_start_timestamp": $TASK_START,
    "timestamp": "$(date -Iseconds)",
    "files": {
        "mask_red": $(get_file_info "$FILE_RED"),
        "mask_green": $(get_file_info "$FILE_GREEN"),
        "mask_overlap": $(get_file_info "$FILE_OVERLAP"),
        "counts_csv": $(get_file_info "$FILE_COUNTS")
    }
}
EOF

# 5. Ensure files are readable for the verifier (copy_from_env)
chmod 644 "$FILE_RED" "$FILE_GREEN" "$FILE_OVERLAP" "$FILE_COUNTS" 2>/dev/null || true
chmod 644 /tmp/boolean_overlap_result.json

echo "Result summary saved to /tmp/boolean_overlap_result.json"
cat /tmp/boolean_overlap_result.json
echo "=== Export Complete ==="