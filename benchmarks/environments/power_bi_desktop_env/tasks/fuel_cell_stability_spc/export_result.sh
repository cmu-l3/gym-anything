#!/bin/bash
echo "=== Exporting Fuel Cell Task Results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TARGET_FILE="/home/ga/Desktop/Voltage_Stability_Report.pbix"

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check File Existence & Timestamp
FILE_EXISTS="false"
FILE_SIZE="0"
FILE_CREATED_DURING="false"

if [ -f "$TARGET_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$TARGET_FILE")
    FILE_MTIME=$(stat -c %Y "$TARGET_FILE")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING="true"
    fi
fi

# 3. Content Analysis (Power BI .pbix is a ZIP file)
# We will extract Layout (JSON) and inspect DataModel (Binary) strings
EXTRACT_DIR="/tmp/pbi_extract"
rm -rf "$EXTRACT_DIR"
mkdir -p "$EXTRACT_DIR"

LAYOUT_JSON="{}"
MODEL_STRINGS=""

if [ "$FILE_EXISTS" = "true" ]; then
    # Unzip specific files we care about
    unzip -q -o "$TARGET_FILE" "Report/Layout" "DataModel" -d "$EXTRACT_DIR" 2>/dev/null || true
    
    # Read Layout JSON if it exists
    if [ -f "$EXTRACT_DIR/Report/Layout" ]; then
        # Convert UTF-16LE to UTF-8 if needed (Power BI sometimes uses it)
        # Using iconv or just cat if it's standard. Usually Layout is JSON.
        # We'll just read it as raw text for python to handle, or cat it here if simple.
        # Let's save it to a file for Python to parse properly.
        mv "$EXTRACT_DIR/Report/Layout" "$EXTRACT_DIR/layout.json"
    fi
    
    # Extract strings from DataModel binary to look for DAX measure names/formulas
    if [ -f "$EXTRACT_DIR/DataModel" ]; then
        # Use strings command to get readable text
        strings "$EXTRACT_DIR/DataModel" > "$EXTRACT_DIR/datamodel_strings.txt"
    fi
fi

# 4. Create Result JSON
# We will embed the layout JSON and data model strings into the result file
# so verifier.py can analyze them.

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 -c "
import json
import os

result = {
    'file_exists': '$FILE_EXISTS' == 'true',
    'file_created_during_task': '$FILE_CREATED_DURING' == 'true',
    'file_size': int('$FILE_SIZE'),
    'layout_content': None,
    'datamodel_strings': ''
}

# Load Layout
if os.path.exists('$EXTRACT_DIR/layout.json'):
    try:
        with open('$EXTRACT_DIR/layout.json', 'rb') as f:
            # Power BI Layout often has BOM or encoding issues, try decode
            content = f.read().decode('utf-16-le', errors='ignore')
            # Sometimes it's utf-8, try that if simple load fails
            if not content.strip().startswith('{'):
                 with open('$EXTRACT_DIR/layout.json', 'r', encoding='utf-8', errors='ignore') as f2:
                    content = f2.read()
            result['layout_content'] = json.loads(content)
    except Exception as e:
        result['layout_error'] = str(e)

# Load Strings
if os.path.exists('$EXTRACT_DIR/datamodel_strings.txt'):
    with open('$EXTRACT_DIR/datamodel_strings.txt', 'r', errors='ignore') as f:
        result['datamodel_strings'] = f.read()

print(json.dumps(result))
" > "$TEMP_JSON"

# Move result to accessible location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="