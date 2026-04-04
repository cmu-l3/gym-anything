#!/bin/bash
echo "=== Exporting ttest_food_expenditure_group results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Define Paths
OUTPUT_TXT="/home/ga/Documents/gretl_output/ttest_results.txt"
OUTPUT_IMG="/home/ga/Documents/gretl_output/food_boxplot.png"
GT_FILE="/tmp/ground_truth_ttest.txt"

# 2. Check Agent Outputs
TXT_EXISTS="false"
TXT_SIZE="0"
TXT_CONTENT=""
if [ -f "$OUTPUT_TXT" ]; then
    TXT_EXISTS="true"
    TXT_SIZE=$(stat -c %s "$OUTPUT_TXT")
    # Read content safely (escape quotes)
    TXT_CONTENT=$(cat "$OUTPUT_TXT" | head -n 50 | base64 -w 0)
fi

IMG_EXISTS="false"
IMG_SIZE="0"
if [ -f "$OUTPUT_IMG" ]; then
    IMG_EXISTS="true"
    IMG_SIZE=$(stat -c %s "$OUTPUT_IMG")
fi

# 3. Generate Ground Truth using gretlcli (headless)
# We calculate the exact t-statistic and means using the same logic the agent should use.
echo "Generating ground truth..."
gretlcli -b - << 'EOF' > "$GT_FILE" 2>&1
open /home/ga/Documents/gretl_data/food.gdt
series high_income = income > median(income)
diff food_exp high_income
EOF

GT_CONTENT=""
if [ -f "$GT_FILE" ]; then
    GT_CONTENT=$(cat "$GT_FILE" | base64 -w 0)
fi

# 4. Check if files were created during the task window
FILE_CREATED_DURING_TASK="false"
if [ "$TXT_EXISTS" = "true" ]; then
    FILE_MTIME=$(stat -c %Y "$OUTPUT_TXT" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 5. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 6. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "txt_exists": $TXT_EXISTS,
    "txt_size": $TXT_SIZE,
    "txt_content_b64": "$TXT_CONTENT",
    "img_exists": $IMG_EXISTS,
    "img_size": $IMG_SIZE,
    "gt_content_b64": "$GT_CONTENT",
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"