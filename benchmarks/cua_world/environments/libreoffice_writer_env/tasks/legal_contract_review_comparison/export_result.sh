#!/bin/bash
set -e

echo "=== Exporting Legal Contract Review Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
COMP_PATH="/home/ga/Documents/contract_comparison.odt"
FINAL_PATH="/home/ga/Documents/contract_final_resolved.odt"

# Check file existence and modification
COMP_EXISTS="false"
COMP_MODIFIED="false"
if [ -f "$COMP_PATH" ]; then
    COMP_EXISTS="true"
    if [ $(stat -c %Y "$COMP_PATH") -gt "$TASK_START" ]; then
        COMP_MODIFIED="true"
    fi
fi

FINAL_EXISTS="false"
FINAL_MODIFIED="false"
if [ -f "$FINAL_PATH" ]; then
    FINAL_EXISTS="true"
    if [ $(stat -c %Y "$FINAL_PATH") -gt "$TASK_START" ]; then
        FINAL_MODIFIED="true"
    fi
fi

# Convert files to text for verification (robust against ODT parsing complexity)
# We use the built-in writer-headless utility or libreoffice directly
echo "Converting documents to text for content verification..."

# Convert final resolved doc
if [ "$FINAL_EXISTS" = "true" ]; then
    timeout 30s libreoffice --headless --convert-to txt --outdir /tmp "$FINAL_PATH" >/dev/null 2>&1 || true
    mv /tmp/contract_final_resolved.txt /tmp/final_content.txt 2>/dev/null || echo "" > /tmp/final_content.txt
else
    echo "" > /tmp/final_content.txt
fi

# We don't convert comparison doc to text because we need to check internal XML for changes, 
# which we'll do in python by copying the ODT (zip) file.

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "comparison_exists": $COMP_EXISTS,
    "comparison_created_during_task": $COMP_MODIFIED,
    "final_exists": $FINAL_EXISTS,
    "final_created_during_task": $FINAL_MODIFIED,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move result to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

# Cleanup text conversion artifact (but keep for copying in verification)
# We leave /tmp/final_content.txt for the verifier to copy

echo "=== Export complete ==="