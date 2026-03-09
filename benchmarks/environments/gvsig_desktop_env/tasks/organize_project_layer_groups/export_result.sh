#!/bin/bash
echo "=== Exporting organize_project_layer_groups result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

PROJECT_PATH="/home/ga/gvsig_data/projects/organized_basemap.gvsproj"
XML_EXTRACT_PATH="/tmp/extracted_project.xml"

# Check if project file exists
PROJECT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
PROJECT_SIZE="0"

if [ -f "$PROJECT_PATH" ]; then
    PROJECT_EXISTS="true"
    PROJECT_SIZE=$(stat -c %s "$PROJECT_PATH" 2>/dev/null || echo "0")
    
    # Check creation time
    PROJECT_MTIME=$(stat -c %Y "$PROJECT_PATH" 2>/dev/null || echo "0")
    if [ "$PROJECT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Try to extract the internal XML project definition
    # gvSIG .gvsproj files are typically ZIP archives containing a project.gvp or similar XML
    echo "Attempting to extract project XML..."
    # We use unzip -p to pipe the content of the first .gvp or .xml file found
    if unzip -l "$PROJECT_PATH" | grep -q ".gvp"; then
        unzip -p "$PROJECT_PATH" "*.gvp" > "$XML_EXTRACT_PATH" 2>/dev/null || true
    elif unzip -l "$PROJECT_PATH" | grep -q ".xml"; then
        unzip -p "$PROJECT_PATH" "*.xml" > "$XML_EXTRACT_PATH" 2>/dev/null || true
    else
        # Fallback: maybe it's not a zip but raw XML (older versions)?
        cp "$PROJECT_PATH" "$XML_EXTRACT_PATH"
    fi
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "project_exists": $PROJECT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "project_size_bytes": $PROJECT_SIZE,
    "screenshot_path": "/tmp/task_final.png",
    "xml_extract_path": "$XML_EXTRACT_PATH"
}
EOF

# Move JSON to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

# Handle the extracted XML file permissions so the verifier can read it
if [ -f "$XML_EXTRACT_PATH" ]; then
    chmod 666 "$XML_EXTRACT_PATH"
fi

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="