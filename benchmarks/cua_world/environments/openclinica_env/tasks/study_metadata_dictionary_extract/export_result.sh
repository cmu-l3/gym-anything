#!/bin/bash
echo "=== Exporting study_metadata_dictionary_extract result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png ga

TASK_START_TIME=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# 1. Check XML File
XML_PATH="/home/ga/study_metadata.xml"
XML_EXISTS="false"
XML_CREATED_DURING_TASK="false"
XML_SIZE=0

if [ -f "$XML_PATH" ]; then
    XML_EXISTS="true"
    XML_MTIME=$(stat -c %Y "$XML_PATH" 2>/dev/null || echo "0")
    XML_SIZE=$(stat -c %s "$XML_PATH" 2>/dev/null || echo "0")
    
    if [ "$XML_MTIME" -ge "$TASK_START_TIME" ]; then
        XML_CREATED_DURING_TASK="true"
    fi
    
    # Copy to tmp for verifier access
    cp "$XML_PATH" /tmp/study_metadata.xml
    chmod 666 /tmp/study_metadata.xml
fi

# 2. Check JSON File
JSON_PATH="/home/ga/ae_codelists.json"
JSON_EXISTS="false"
JSON_CREATED_DURING_TASK="false"
JSON_SIZE=0

if [ -f "$JSON_PATH" ]; then
    JSON_EXISTS="true"
    JSON_MTIME=$(stat -c %Y "$JSON_PATH" 2>/dev/null || echo "0")
    JSON_SIZE=$(stat -c %s "$JSON_PATH" 2>/dev/null || echo "0")
    
    if [ "$JSON_MTIME" -ge "$TASK_START_TIME" ]; then
        JSON_CREATED_DURING_TASK="true"
    fi
    
    # Copy to tmp for verifier access
    cp "$JSON_PATH" /tmp/ae_codelists.json
    chmod 666 /tmp/ae_codelists.json
fi

# Create result payload
TEMP_JSON=$(mktemp /tmp/metadata_extract_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "xml_exists": $XML_EXISTS,
    "xml_created_during_task": $XML_CREATED_DURING_TASK,
    "xml_size_bytes": $XML_SIZE,
    "json_exists": $JSON_EXISTS,
    "json_created_during_task": $JSON_CREATED_DURING_TASK,
    "json_size_bytes": $JSON_SIZE,
    "screenshot_path": "/tmp/task_end_screenshot.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to standard location accessible to verifier
rm -f /tmp/metadata_extract_result.json 2>/dev/null || sudo rm -f /tmp/metadata_extract_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/metadata_extract_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/metadata_extract_result.json
chmod 666 /tmp/metadata_extract_result.json 2>/dev/null || sudo chmod 666 /tmp/metadata_extract_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/metadata_extract_result.json"
echo "=== Export Complete ==="