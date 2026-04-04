#!/bin/bash
echo "=== Exporting Hierarchical Clustering results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/Documents/JASP/HierarchicalClustering_BigFive.jasp"

# Check output file status
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c%s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c%Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    else
        CREATED_DURING_TASK="false"
    fi
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    CREATED_DURING_TASK="false"
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Prepare result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "output_exists": $OUTPUT_EXISTS,
    "output_size_bytes": $OUTPUT_SIZE,
    "created_during_task": $CREATED_DURING_TASK,
    "output_path": "$OUTPUT_PATH",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Ensure permissions are correct for copy_from_env
chmod 644 /tmp/task_result.json 2>/dev/null || true
if [ -f "$OUTPUT_PATH" ]; then
    chmod 644 "$OUTPUT_PATH" 2>/dev/null || true
fi

echo "Result metadata saved to /tmp/task_result.json"
echo "=== Export complete ==="