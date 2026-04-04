#!/bin/bash
echo "=== Exporting Botanical Morphometry Results ==="

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Paths
RES_DIR="/home/ga/Fiji_Data/results/botany"
CSV_FILE="$RES_DIR/measurements.csv"
IMG_FILE="$RES_DIR/annotated_leaf.png"
MASK_FILE="$RES_DIR/leaf_mask.png"
GT_FILE="/var/lib/app/ground_truth/botany_truth.json"
TASK_START_FILE="/tmp/task_start_time.txt"

# 3. Check Timestamps
TASK_START=$(cat "$TASK_START_FILE" 2>/dev/null || echo "0")

check_file() {
    local f="$1"
    if [ -f "$f" ]; then
        local mtime=$(stat -c %Y "$f")
        if [ "$mtime" -gt "$TASK_START" ]; then
            echo "true"
        else
            echo "false"
        fi
    else
        echo "false"
    fi
}

CSV_CREATED=$(check_file "$CSV_FILE")
IMG_CREATED=$(check_file "$IMG_FILE")
MASK_CREATED=$(check_file "$MASK_FILE")

# 4. Read File Sizes
CSV_SIZE=$(stat -c %s "$CSV_FILE" 2>/dev/null || echo "0")
IMG_SIZE=$(stat -c %s "$IMG_FILE" 2>/dev/null || echo "0")

# 5. Extract Ground Truth
GT_AREA="0"
if [ -f "$GT_FILE" ]; then
    # Simple grep/sed extraction since jq might not be installed
    GT_AREA=$(grep -o '"area_cm2": [0-9.]*' "$GT_FILE" | cut -d' ' -f2)
fi

# 6. Prepare Export JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat << EOF > "$TEMP_JSON"
{
    "task_start": $TASK_START,
    "csv_exists": $([ -f "$CSV_FILE" ] && echo "true" || echo "false"),
    "csv_created_during_task": $CSV_CREATED,
    "csv_path": "$CSV_FILE",
    "image_exists": $([ -f "$IMG_FILE" ] && echo "true" || echo "false"),
    "image_created_during_task": $IMG_CREATED,
    "image_path": "$IMG_FILE",
    "mask_exists": $([ -f "$MASK_FILE" ] && echo "true" || echo "false"),
    "ground_truth_area_cm2": ${GT_AREA:-0}
}
EOF

# 7. Move Result for Verifier
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

# 8. Copy outputs to tmp for verifier access via copy_from_env
if [ -f "$CSV_FILE" ]; then cp "$CSV_FILE" /tmp/measurements.csv; chmod 666 /tmp/measurements.csv; fi
if [ -f "$IMG_FILE" ]; then cp "$IMG_FILE" /tmp/annotated_leaf.png; chmod 666 /tmp/annotated_leaf.png; fi
if [ -f "$MASK_FILE" ]; then cp "$MASK_FILE" /tmp/leaf_mask.png; chmod 666 /tmp/leaf_mask.png; fi

echo "Export complete. Result saved to /tmp/task_result.json"