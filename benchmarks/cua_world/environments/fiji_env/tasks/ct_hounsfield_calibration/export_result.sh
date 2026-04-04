#!/bin/bash
echo "=== Exporting CT Calibration Results ==="

# 1. Timestamps
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 2. Paths
RESULT_DIR="/home/ga/Fiji_Data/results/ct"
IMG_PATH="$RESULT_DIR/calibrated_ct.tif"
MASK_PATH="$RESULT_DIR/bone_mask.png"
CSV_PATH="$RESULT_DIR/density_report.csv"
GT_PATH="/tmp/ct_ground_truth.json"

# 3. Check Files
IMG_EXISTS="false"
IMG_MODIFIED="false"
if [ -f "$IMG_PATH" ]; then
    IMG_EXISTS="true"
    MTIME=$(stat -c %Y "$IMG_PATH")
    if [ "$MTIME" -gt "$TASK_START" ]; then IMG_MODIFIED="true"; fi
fi

MASK_EXISTS="false"
if [ -f "$MASK_PATH" ]; then MASK_EXISTS="true"; fi

CSV_EXISTS="false"
if [ -f "$CSV_PATH" ]; then CSV_EXISTS="true"; fi

# 4. Copy Ground Truth (Hidden)
cp "$GT_PATH" /tmp/ground_truth.json 2>/dev/null || echo "{}" > /tmp/ground_truth.json

# 5. Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 6. JSON Export
cat << EOF > /tmp/task_result.json
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "image_exists": $IMG_EXISTS,
    "image_modified": $IMG_MODIFIED,
    "mask_exists": $MASK_EXISTS,
    "csv_exists": $CSV_EXISTS,
    "image_path": "$IMG_PATH",
    "mask_path": "$MASK_PATH",
    "csv_path": "$CSV_PATH",
    "ground_truth_path": "/tmp/ground_truth.json"
}
EOF

# Permissions
chmod 644 /tmp/task_result.json
chmod 644 /tmp/ground_truth.json
if [ -f "$IMG_PATH" ]; then cp "$IMG_PATH" /tmp/calibrated_ct.tif; chmod 644 /tmp/calibrated_ct.tif; fi
if [ -f "$MASK_PATH" ]; then cp "$MASK_PATH" /tmp/bone_mask.png; chmod 644 /tmp/bone_mask.png; fi
if [ -f "$CSV_PATH" ]; then cp "$CSV_PATH" /tmp/density_report.csv; chmod 644 /tmp/density_report.csv; fi

echo "Results exported to /tmp/task_result.json"