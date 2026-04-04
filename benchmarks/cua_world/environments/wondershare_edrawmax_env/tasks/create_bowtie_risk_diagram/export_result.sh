#!/bin/bash
echo "=== Exporting Create BowTie Risk Diagram results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final state screenshot
take_screenshot /tmp/task_final.png

# 2. Check file existence and timestamps
EDDX_PATH="/home/ga/Documents/ransomware_bowtie.eddx"
PDF_PATH="/home/ga/Documents/ransomware_bowtie.pdf"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

EDDX_EXISTS="false"
EDDX_SIZE="0"
EDDX_CREATED_DURING="false"

if [ -f "$EDDX_PATH" ]; then
    EDDX_EXISTS="true"
    EDDX_SIZE=$(stat -c %s "$EDDX_PATH")
    FILE_MTIME=$(stat -c %Y "$EDDX_PATH")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        EDDX_CREATED_DURING="true"
    fi
fi

PDF_EXISTS="false"
PDF_SIZE="0"
PDF_CREATED_DURING="false"

if [ -f "$PDF_PATH" ]; then
    PDF_EXISTS="true"
    PDF_SIZE=$(stat -c %s "$PDF_PATH")
    FILE_MTIME=$(stat -c %Y "$PDF_PATH")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        PDF_CREATED_DURING="true"
    fi
fi

# 3. Prepare result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "eddx_exists": $EDDX_EXISTS,
    "eddx_size": $EDDX_SIZE,
    "eddx_created_during_task": $EDDX_CREATED_DURING,
    "pdf_exists": $PDF_EXISTS,
    "pdf_size": $PDF_SIZE,
    "pdf_created_during_task": $PDF_CREATED_DURING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 4. Save to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Results exported to /tmp/task_result.json"