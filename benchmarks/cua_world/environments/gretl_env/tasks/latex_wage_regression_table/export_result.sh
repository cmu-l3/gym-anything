#!/bin/bash
echo "=== Exporting latex_wage_regression_table results ==="

source /workspace/scripts/task_utils.sh

OUTPUT_FILE="/home/ga/Documents/gretl_output/wage_models.tex"

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Check output file status
OUTPUT_EXISTS="false"
OUTPUT_SIZE="0"
FILE_CONTENT_PREVIEW=""

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c%s "$OUTPUT_FILE")
    # Read first 20 lines for debug/logging
    FILE_CONTENT_PREVIEW=$(head -n 20 "$OUTPUT_FILE" | base64 -w 0)
fi

# 3. Check if Gretl is still running
APP_RUNNING=$(pgrep -f "gretl" > /dev/null && echo "true" || echo "false")

# 4. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "output_exists": $OUTPUT_EXISTS,
    "output_size": $OUTPUT_SIZE,
    "app_running": $APP_RUNNING,
    "output_path": "$OUTPUT_FILE",
    "timestamp": $(date +%s)
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "=== Export Complete ==="