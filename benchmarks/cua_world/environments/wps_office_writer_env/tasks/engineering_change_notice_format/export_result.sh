#!/bin/bash
set -euo pipefail

echo "=== Exporting ECN Format Result ==="

DOC_PATH="/home/ga/Documents/ECN-2024-0847_final.docx"
DOC_EXISTS="false"
DOC_SIZE="0"
DOC_MTIME="0"

# Take final screenshot
DISPLAY=:1 scrot /tmp/ecn_task_final.png 2>/dev/null || true

# Check if target document was created
if [ -f "$DOC_PATH" ]; then
    DOC_EXISTS="true"
    DOC_SIZE=$(stat -c %s "$DOC_PATH" 2>/dev/null || echo "0")
    DOC_MTIME=$(stat -c %Y "$DOC_PATH" 2>/dev/null || echo "0")
    
    # Copy to a safe location for the verifier to pull
    cp "$DOC_PATH" /tmp/ECN-2024-0847_final.docx
    chmod 666 /tmp/ECN-2024-0847_final.docx
    echo "Document successfully copied to /tmp/"
else
    echo "Document not found at $DOC_PATH"
fi

TASK_START=$(cat /tmp/ecn_task_start_ts 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Create JSON metadata file
TEMP_JSON=$(mktemp /tmp/ecn_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "document_exists": $DOC_EXISTS,
    "document_path": "$DOC_PATH",
    "document_size": $DOC_SIZE,
    "document_mtime": $DOC_MTIME,
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "screenshot_path": "/tmp/ecn_task_final.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 "$TEMP_JSON"
mv "$TEMP_JSON" /tmp/ecn_task_result.json

# Attempt to cleanly close WPS Office
echo "Closing WPS Writer..."
WID=$(DISPLAY=:1 wmctrl -l | grep -i "WPS Writer\|ECN-2024-0847" | awk '{print $1}' | head -1 || echo "")
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ic "$WID" 2>/dev/null || true
    sleep 2
    # Dismiss any save dialogs that pop up during close
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
fi

echo "=== Export Complete ==="