#!/bin/bash
# Export script for Wound Healing Analysis
set -e

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting Task Results ==="

# 1. Basic Task Info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 2. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 3. Check Output Files
MASK_PATH="/home/ga/ImageJ_Data/results/wound_mask.tif"
CSV_PATH="/home/ga/ImageJ_Data/results/wound_results.csv"

MASK_EXISTS="false"
CSV_EXISTS="false"
MASK_TIMESTAMP=0
CSV_TIMESTAMP=0
MASK_SIZE=0

if [ -f "$MASK_PATH" ]; then
    MASK_EXISTS="true"
    MASK_TIMESTAMP=$(stat -c %Y "$MASK_PATH")
    MASK_SIZE=$(stat -c %s "$MASK_PATH")
fi

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_TIMESTAMP=$(stat -c %Y "$CSV_PATH")
fi

# 4. Capture Window State (to verify tools used)
WINDOW_LIST=$(DISPLAY=:1 wmctrl -l 2>/dev/null || echo "No windows")

# 5. Create Metadata JSON
# We don't analyze the image here (no numpy in bash). 
# We export file metadata; verifier.py will pull the actual files.
cat > /tmp/task_result.json <<EOF
{
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "mask_exists": $MASK_EXISTS,
  "csv_exists": $CSV_EXISTS,
  "mask_timestamp": $MASK_TIMESTAMP,
  "csv_timestamp": $CSV_TIMESTAMP,
  "mask_size_bytes": $MASK_SIZE,
  "window_list": "$(echo "$WINDOW_LIST" | tr '\n' '|' | sed 's/"/\\"/g')",
  "original_image_path": "/home/ga/ImageJ_Data/raw/scratch_assay.tif",
  "mask_image_path": "$MASK_PATH",
  "csv_path": "$CSV_PATH"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Export complete. JSON summary at /tmp/task_result.json"