#!/bin/bash
echo "=== Exporting ESI Triage Task Result ==="

# 1. Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Gather File Statistics
DIAGRAM_PATH="/home/ga/Diagrams/esi_triage_tree.drawio"
PNG_PATH="/home/ga/Diagrams/exports/esi_triage_tree.png"
SVG_PATH="/home/ga/Diagrams/exports/esi_triage_tree.svg"

# Check diagram
if [ -f "$DIAGRAM_PATH" ]; then
    DIAGRAM_EXISTS="true"
    DIAGRAM_SIZE=$(stat -c %s "$DIAGRAM_PATH")
    DIAGRAM_MTIME=$(stat -c %Y "$DIAGRAM_PATH")
    
    # Check if modified vs initial
    INITIAL_HASH=$(cat /tmp/initial_hash.txt | cut -d' ' -f1)
    CURRENT_HASH=$(md5sum "$DIAGRAM_PATH" | cut -d' ' -f1)
    if [ "$INITIAL_HASH" != "$CURRENT_HASH" ]; then
        MODIFIED="true"
    else
        MODIFIED="false"
    fi
else
    DIAGRAM_EXISTS="false"
    DIAGRAM_SIZE=0
    DIAGRAM_MTIME=0
    MODIFIED="false"
fi

# Check exports
if [ -f "$PNG_PATH" ]; then PNG_EXISTS="true"; else PNG_EXISTS="false"; fi
if [ -f "$SVG_PATH" ]; then SVG_EXISTS="true"; else SVG_EXISTS="false"; fi

# 3. Create JSON Result
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "diagram_exists": $DIAGRAM_EXISTS,
    "diagram_size": $DIAGRAM_SIZE,
    "diagram_modified": $MODIFIED,
    "png_exported": $PNG_EXISTS,
    "svg_exported": $SVG_EXISTS
}
EOF

# Move to standard location with lenient permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/task_result.json"