#!/bin/bash
echo "=== Exporting Evaluate Lesion Aspect Ratio result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
EXPORT_DIR="/home/ga/DICOM/exports"
REPORT_PATH="$EXPORT_DIR/aspect_ratio_report.txt"

REPORT_EXISTS="false"
REPORT_MODIFIED_DURING_TASK="false"
EXPORT_IMAGE_EXISTS="false"
EXPORT_IMAGE_PATH=""

# 1. Check Report File
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -ge "$TASK_START" ]; then
        REPORT_MODIFIED_DURING_TASK="true"
    fi
    # Copy to tmp for the verifier
    cp "$REPORT_PATH" /tmp/report.txt 2>/dev/null || true
fi

# 2. Check Exported Image (JPG or PNG)
for ext in jpg jpeg png JPG JPEG PNG; do
    if [ -f "$EXPORT_DIR/aspect_ratio_view.$ext" ]; then
        EXPORT_IMAGE_EXISTS="true"
        EXPORT_IMAGE_PATH="$EXPORT_DIR/aspect_ratio_view.$ext"
        # Copy to tmp for the verifier
        cp "$EXPORT_IMAGE_PATH" /tmp/exported_view.img 2>/dev/null || true
        break
    fi
done

# Take final desktop screenshot as fallback
take_screenshot /tmp/task_final.png

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "report_exists": $REPORT_EXISTS,
    "report_modified_during_task": $REPORT_MODIFIED_DURING_TASK,
    "export_image_exists": $EXPORT_IMAGE_EXISTS,
    "export_image_path": "$EXPORT_IMAGE_PATH",
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="