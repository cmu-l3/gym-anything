#!/bin/bash
# Export script for fillable_hr_form_create task

echo "=== Exporting Fillable HR Form Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
take_screenshot /tmp/task_final.png 2>/dev/null || true

OUTPUT_FILE="/home/ga/Documents/Apex_New_Hire_Form.odt"
RESULT_JSON="/tmp/task_result.json"

# Check if file exists and get stats
if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_FILE")
    # Verify modification time
    TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_FILE")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    else
        CREATED_DURING_TASK="false"
    fi
else
    FILE_EXISTS="false"
    FILE_SIZE="0"
    CREATED_DURING_TASK="false"
fi

# Use Python to parse the ODT XML and count form controls
python3 << PYEOF
import zipfile
import json
import re
import os

output_file = "$OUTPUT_FILE"
result = {
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "created_during_task": $CREATED_DURING_TASK,
    "has_forms_xml": False,
    "control_counts": {
        "text_box": 0,
        "checkbox": 0,
        "date_field": 0,
        "formatted_text": 0
    },
    "text_content_found": False,
    "company_name_found": False
}

if result["file_exists"] and result["file_size"] > 0:
    try:
        with zipfile.ZipFile(output_file, 'r') as z:
            # ODT structure: content.xml holds the document body and form controls
            content_xml = z.read('content.xml').decode('utf-8', errors='ignore')
            
            # 1. Check for forms definition section
            if '<office:forms' in content_xml:
                result["has_forms_xml"] = True
            
            # 2. Count Controls using Regex (Namespaces can vary, usually form: or dom:form)
            # Text boxes
            result["control_counts"]["text_box"] = len(re.findall(r'<form:text\b', content_xml))
            
            # Checkboxes
            result["control_counts"]["checkbox"] = len(re.findall(r'<form:checkbox\b', content_xml))
            
            # Date fields (can be form:date or form:formatted-text with date style)
            result["control_counts"]["date_field"] = len(re.findall(r'<form:date\b', content_xml))
            result["control_counts"]["formatted_text"] = len(re.findall(r'<form:formatted-text\b', content_xml))
            
            # 3. Check for text content
            plain_text = re.sub(r'<[^>]+>', ' ', content_xml).lower()
            if "apex" in plain_text and "structural" in plain_text:
                result["company_name_found"] = True
            
            # Simple check if instructions or labels exist
            if "new hire" in plain_text:
                result["text_content_found"] = True

    except Exception as e:
        result["error"] = str(e)

# Save result
with open('$RESULT_JSON', 'w') as f:
    json.dump(result, f)
PYEOF

# Handle permissions
chmod 666 "$RESULT_JSON" 2>/dev/null || true

echo "Result saved to $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export Complete ==="