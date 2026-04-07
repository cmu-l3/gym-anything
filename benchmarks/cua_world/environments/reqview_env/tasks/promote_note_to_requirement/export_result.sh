#!/bin/bash
echo "=== Exporting promote_note_to_requirement results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Record timestamp info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Check file modification time of SRS.json
# (The verifier needs to know if the file was actually saved)
PROJECT_DIR="/home/ga/Documents/ReqView/promote_note_project"
SRS_JSON="$PROJECT_DIR/documents/SRS.json"

FILE_MODIFIED="false"
SRS_MTIME=0

if [ -f "$SRS_JSON" ]; then
    SRS_MTIME=$(stat -c %Y "$SRS_JSON" 2>/dev/null || echo "0")
    if [ "$SRS_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# 4. Create simple JSON report for metadata (verifier does heavy lifting)
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "srs_modified": $FILE_MODIFIED,
    "srs_mtime": $SRS_MTIME,
    "screenshot_path": "/tmp/task_final.png",
    "project_path": "$PROJECT_DIR"
}
EOF

echo "Export complete. Result:"
cat /tmp/task_result.json