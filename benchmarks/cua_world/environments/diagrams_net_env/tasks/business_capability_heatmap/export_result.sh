#!/bin/bash
echo "=== Exporting Business Capability Heatmap Result ==="

# Paths
DRAWIO_FILE="/home/ga/Diagrams/capability_map.drawio"
PDF_FILE="/home/ga/Diagrams/capability_map.pdf"
RESULT_JSON="/tmp/task_result.json"
START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check file existence and timestamps
EXISTS_DRAWIO=false
MODIFIED_DRAWIO=false
EXISTS_PDF=false

if [ -f "$DRAWIO_FILE" ]; then
    EXISTS_DRAWIO=true
    MTIME=$(stat -c %Y "$DRAWIO_FILE")
    if [ "$MTIME" -gt "$START_TIME" ]; then
        MODIFIED_DRAWIO=true
    fi
fi

if [ -f "$PDF_FILE" ]; then
    EXISTS_PDF=true
fi

# Prepare result JSON
# We do minimal processing here; the complex parsing happens in verifier.py
# which reads the actual .drawio file via copy_from_env.
cat > "$RESULT_JSON" << EOF
{
    "drawio_exists": $EXISTS_DRAWIO,
    "drawio_modified": $MODIFIED_DRAWIO,
    "pdf_exists": $EXISTS_PDF,
    "task_start_time": $START_TIME,
    "drawio_path": "$DRAWIO_FILE",
    "pdf_path": "$PDF_FILE"
}
EOF

# Ensure permissions for copy_from_env
chmod 644 "$RESULT_JSON"
if [ -f "$DRAWIO_FILE" ]; then
    chmod 644 "$DRAWIO_FILE"
fi

echo "Result exported to $RESULT_JSON"