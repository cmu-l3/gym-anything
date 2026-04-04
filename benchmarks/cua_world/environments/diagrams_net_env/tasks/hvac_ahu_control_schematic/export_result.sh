#!/bin/bash
echo "=== Exporting HVAC Schematic Results ==="

# Files
SOURCE_FILE="/home/ga/Diagrams/AHU-1_Schematic.drawio"
PDF_FILE="/home/ga/Diagrams/AHU-1_Schematic.pdf"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot (Evidence of UI state)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check File Stats
SOURCE_EXISTS="false"
PDF_EXISTS="false"
FILE_MODIFIED="false"
SOURCE_SIZE=0

if [ -f "$SOURCE_FILE" ]; then
    SOURCE_EXISTS="true"
    SOURCE_SIZE=$(stat -c %s "$SOURCE_FILE")
    MTIME=$(stat -c %Y "$SOURCE_FILE")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

if [ -f "$PDF_FILE" ] && [ $(stat -c %s "$PDF_FILE") -gt 100 ]; then
    PDF_EXISTS="true"
fi

# 3. Prepare result JSON
# We will embed the raw file content (if small enough) or extracted text for the verifier
# to parse, since the verifier runs outside the container.
# However, for draw.io files which are compressed XML, we should try to uncompress them here 
# if possible, OR just copy the file out using the verifier's copy_from_env mechanism.
# The standard pattern is to generate a JSON with METADATA here, and let the verifier 
# pull the actual file if needed.

cat > /tmp/task_result.json << EOF
{
    "source_exists": $SOURCE_EXISTS,
    "pdf_exists": $PDF_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "source_size": $SOURCE_SIZE,
    "task_start_time": $TASK_START,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Set permissions so verifier can read/copy
chmod 644 /tmp/task_result.json
if [ -f "$SOURCE_FILE" ]; then
    chmod 644 "$SOURCE_FILE"
fi

echo "=== Export complete ==="