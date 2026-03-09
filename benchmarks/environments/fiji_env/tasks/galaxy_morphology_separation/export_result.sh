#!/bin/bash
echo "=== Exporting Galaxy Morphology Results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULTS_DIR="/home/ga/Fiji_Data/results/galaxy"
CSV_FILE="$RESULTS_DIR/companion_metrics.csv"
IMG_FILE="$RESULTS_DIR/segmentation_map.png"
JSON_OUT="/tmp/galaxy_result.json"

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check CSV
CSV_EXISTS="false"
CSV_CREATED_DURING="false"
if [ -f "$CSV_FILE" ]; then
    CSV_EXISTS="true"
    MTIME=$(stat -c %Y "$CSV_FILE")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        CSV_CREATED_DURING="true"
    fi
fi

# Check Image
IMG_EXISTS="false"
IMG_CREATED_DURING="false"
if [ -f "$IMG_FILE" ]; then
    IMG_EXISTS="true"
    MTIME=$(stat -c %Y "$IMG_FILE")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        IMG_CREATED_DURING="true"
    fi
fi

# Prepare result JSON
cat > "$JSON_OUT" << EOF
{
    "task_start": $TASK_START,
    "csv_exists": $CSV_EXISTS,
    "csv_created_during_task": $CSV_CREATED_DURING,
    "img_exists": $IMG_EXISTS,
    "img_created_during_task": $IMG_CREATED_DURING,
    "screenshot_path": "/tmp/task_final.png",
    "csv_path": "$CSV_FILE",
    "img_path": "$IMG_FILE"
}
EOF

# Set permissions so python verifier can read it
chmod 644 "$JSON_OUT" "$CSV_FILE" "$IMG_FILE" 2>/dev/null || true

echo "Export complete. JSON saved to $JSON_OUT"