#!/bin/bash
set -euo pipefail

echo "=== Exporting CBA Ratification Redline Result ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

OUTPUT_DOC="/home/ga/Documents/CBA_Tentative_Agreement.docx"
DOC_EXISTS="false"
DOC_CREATED_DURING_TASK="false"
DOC_SIZE=0

if [ -f "$OUTPUT_DOC" ]; then
    DOC_EXISTS="true"
    DOC_SIZE=$(stat -c %s "$OUTPUT_DOC")
    DOC_MTIME=$(stat -c %Y "$OUTPUT_DOC")
    
    if [ "$DOC_MTIME" -gt "$TASK_START" ]; then
        DOC_CREATED_DURING_TASK="true"
    fi
    
    # Copy to tmp for verifier parsing
    cp "$OUTPUT_DOC" /tmp/cba_output.docx
    chmod 666 /tmp/cba_output.docx
fi

cat > /tmp/cba_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "doc_exists": $DOC_EXISTS,
    "doc_created_during_task": $DOC_CREATED_DURING_TASK,
    "doc_size_bytes": $DOC_SIZE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

chmod 666 /tmp/cba_result.json

echo "Result saved to /tmp/cba_result.json"
cat /tmp/cba_result.json

echo "=== Export complete ==="