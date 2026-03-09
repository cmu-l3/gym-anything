#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting model_comparison_aic_bic results ==="

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_FILE="/home/ga/Documents/gretl_output/model_comparison.txt"

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check output file status
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_CONTENT=""

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    # Read content, escape quotes for JSON inclusion
    OUTPUT_CONTENT=$(cat "$OUTPUT_FILE" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
    
    # Check modification time
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
else
    OUTPUT_CONTENT="\"\""
fi

# 3. Check if Gretl is still running
APP_RUNNING=$(pgrep -f "gretl" > /dev/null && echo "true" || echo "false")

# 4. GENERATE GROUND TRUTH VALUES inside the environment
# We run the actual analysis using gretlcli to get the exact correct values 
# for this specific version/environment.
GT_SCRIPT="/tmp/gt_calc.inp"
cat > "$GT_SCRIPT" << 'HANSL_EOF'
open /home/ga/Documents/gretl_data/food.gdt
# Model 1: Linear
ols food_exp const income --quiet
scalar aic1 = $aic
scalar bic1 = $bic
# Model 2: Quadratic
series income_sq = income^2
ols food_exp const income income_sq --quiet
scalar aic2 = $aic
scalar bic2 = $bic
# Model 3: Square Root
series sqrt_income = sqrt(income)
ols food_exp const sqrt_income --quiet
scalar aic3 = $aic
scalar bic3 = $bic
# Print as JSON object
printf "{\"aic1\": %.4f, \"bic1\": %.4f, \"aic2\": %.4f, \"bic2\": %.4f, \"aic3\": %.4f, \"bic3\": %.4f}\n", aic1, bic1, aic2, bic2, aic3, bic3
HANSL_EOF

# Run ground truth script
GT_JSON="{}"
if command -v gretlcli >/dev/null; then
    # Capture only the JSON line
    GT_JSON=$(gretlcli -b "$GT_SCRIPT" 2>/dev/null | grep "^{" || echo "{}")
fi

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "app_was_running": $APP_RUNNING,
    "output_content": $OUTPUT_CONTENT,
    "ground_truth": $GT_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="