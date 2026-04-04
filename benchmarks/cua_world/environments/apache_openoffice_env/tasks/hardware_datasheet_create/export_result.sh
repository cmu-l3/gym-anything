#!/bin/bash
set -e

echo "=== Exporting Hardware Datasheet Result ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Define Paths
OUTPUT_FILE="/home/ga/Documents/SE9042_Datasheet.odt"
RESULT_JSON="/tmp/task_result.json"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Analyze ODT File using Python
# We use Python to unzip the ODT and parse content.xml and styles.xml
# This allows us to check for specific technical content and formatting tags (columns)
python3 << PYEOF
import json
import os
import zipfile
import re
import sys

output_path = "$OUTPUT_FILE"
task_start = $TASK_START
result = {
    "file_exists": False,
    "file_size": 0,
    "file_created_during_task": False,
    "content_found": [],
    "columns_detected": False,
    "table_detected": False,
    "footer_detected": False,
    "error": None
}

if os.path.exists(output_path):
    result["file_exists"] = True
    stats = os.stat(output_path)
    result["file_size"] = stats.st_size
    
    # Check modification time
    if stats.st_mtime > task_start:
        result["file_created_during_task"] = True

    try:
        with zipfile.ZipFile(output_path, 'r') as z:
            # Read Content XML (Body text)
            content_xml = z.read('content.xml').decode('utf-8', errors='ignore')
            # Read Styles XML (Page layouts, footers)
            styles_xml = z.read('styles.xml').decode('utf-8', errors='ignore')
            
            # Combine for search
            full_text_search = content_xml + styles_xml
            
            # 1. Check for specific content strings
            targets = ["SE-9042", "Preliminary", "-148 dBm", "4.6 mA", "100 nA", "SiliconEdge"]
            found_list = []
            for t in targets:
                if t in full_text_search:
                    found_list.append(t)
            result["content_found"] = found_list
            
            # 2. Check for Table (<table:table>)
            if "<table:table" in content_xml:
                result["table_detected"] = True
                
            # 3. Check for Footer
            # Footers are usually in styles.xml under <style:footer> or content.xml if specific
            # We look for the footer text specifically
            if "SiliconEdge Solutions - Confidential" in full_text_search:
                result["footer_detected"] = True
                
            # 4. Check for Columns
            # OpenOffice uses style:column-count="2" in style:page-layout-properties (styles.xml)
            # OR in style:section-properties (content.xml)
            column_pattern = r'style:column-count="2"'
            if re.search(column_pattern, content_xml) or re.search(column_pattern, styles_xml):
                result["columns_detected"] = True

    except Exception as e:
        result["error"] = str(e)

# Save result
with open("$RESULT_JSON", "w") as f:
    json.dump(result, f, indent=2)

PYEOF

# 4. Set Permissions for Copy
chmod 666 "$RESULT_JSON"

echo "Result exported to $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export Complete ==="