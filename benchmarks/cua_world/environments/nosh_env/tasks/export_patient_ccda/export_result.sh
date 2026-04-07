#!/bin/bash
# Export script for export_patient_ccda task

echo "=== Exporting Task Result ==="

# Source variables
OUTPUT_PATH="/home/ga/Documents/maria_rodriguez_ccda.xml"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Initialize result variables
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"
IS_XML="false"
CONTAINS_PATIENT_NAME="false"
XML_PARSING_ERROR=""

# Check if file exists
if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")

    # Check timestamp
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # Check basic XML validity and content using Python
    # We use a small python script embedded here to avoid dependencies issues
    PYTHON_CHECK=$(python3 -c "
import sys
import xml.etree.ElementTree as ET

try:
    tree = ET.parse('$OUTPUT_PATH')
    root = tree.getroot()
    is_xml = True
    
    # Simple check for text content in the file
    with open('$OUTPUT_PATH', 'r') as f:
        content = f.read()
    
    # Check for patient name 'Maria' and 'Rodriguez'
    # CCDA structure can be complex, so a text search is a robust fallback 
    # if specific path navigation fails, but let's try to be accurate if possible.
    # However, for this check, simple existence in the file is strong evidence 
    # combined with the XML parse check.
    
    has_name = 'Maria' in content and 'Rodriguez' in content
    
    print(f'true|{str(has_name).lower()}|none')
except ET.ParseError as e:
    print(f'false|false|{str(e)}')
except Exception as e:
    print(f'false|false|{str(e)}')
")

    # Parse python output: is_xml|contains_name|error
    IFS='|' read -r IS_XML CONTAINS_PATIENT_NAME XML_PARSING_ERROR <<< "$PYTHON_CHECK"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_path": "$OUTPUT_PATH",
    "file_size_bytes": $FILE_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "is_valid_xml": $IS_XML,
    "contains_patient_name": $CONTAINS_PATIENT_NAME,
    "xml_error": "$XML_PARSING_ERROR",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save to final location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="