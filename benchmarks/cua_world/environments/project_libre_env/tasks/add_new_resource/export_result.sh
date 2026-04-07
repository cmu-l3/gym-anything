#!/bin/bash
echo "=== Exporting Task Results ==="

# 1. Capture final screenshot (evidence of state)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Gather file system evidence
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_FILE="/home/ga/Projects/updated_project.xml"

FILE_EXISTS=false
FILE_SIZE=0
FILE_CREATED_DURING_TASK=false

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS=true
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK=true
    fi
    
    # Copy the XML file to /tmp for easier extraction by verifier
    # (Handling permissions to ensure it's readable)
    cp "$OUTPUT_FILE" /tmp/submitted_project.xml
    chmod 644 /tmp/submitted_project.xml
fi

# 3. Create JSON result
# We use a temp file and move it to avoid partial writes/permission issues
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_size_bytes": $FILE_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "screenshot_path": "/tmp/task_final.png",
    "xml_export_path": "/tmp/submitted_project.xml"
}
EOF

mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Results exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="