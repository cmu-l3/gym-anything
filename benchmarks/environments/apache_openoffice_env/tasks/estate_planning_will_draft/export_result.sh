#!/bin/bash
echo "=== Exporting Estate Planning Result ==="
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

OUTPUT_PATH="/home/ga/Documents/Draft_Will_Thorne.odt"
RESULT_JSON="/tmp/task_result.json"

# Take final screenshot
take_screenshot /tmp/task_final.png 2>/dev/null || true

# Python script to analyze the ODT file
python3 << PYEOF
import zipfile
import json
import os
import re
import sys

output_path = "$OUTPUT_PATH"
task_start = int("$TASK_START")
result = {
    "file_exists": False,
    "file_valid": False,
    "content_analysis": {},
    "formatting_analysis": {},
    "timestamp_valid": False
}

if os.path.exists(output_path):
    result["file_exists"] = True
    
    # Check modification time
    mtime = int(os.path.getmtime(output_path))
    if mtime > task_start:
        result["timestamp_valid"] = True

    try:
        # Open ODT (it's a zip)
        with zipfile.ZipFile(output_path, 'r') as z:
            # Read content.xml for body text
            content_xml = z.read('content.xml').decode('utf-8')
            
            # Read styles.xml for footer/styles
            styles_xml = ""
            if 'styles.xml' in z.namelist():
                styles_xml = z.read('styles.xml').decode('utf-8')

            # --- Formatting Analysis ---
            # Check for Heading 1 style usage: <text:h ... text:outline-level="1">
            h1_count = len(re.findall(r'<text:h[^>]*text:outline-level="1"', content_xml))
            # Check for Heading 2 style usage: <text:h ... text:outline-level="2">
            h2_count = len(re.findall(r'<text:h[^>]*text:outline-level="2"', content_xml))
            
            # Check for Page Numbers in footer
            # Usually <text:page-number> inside styles.xml (master page footer) or content.xml
            has_page_numbers = ('<text:page-number' in styles_xml) or ('<text:page-number' in content_xml)

            result["formatting_analysis"] = {
                "h1_count": h1_count,
                "h2_count": h2_count,
                "has_page_numbers": has_page_numbers
            }

            # --- Content Analysis ---
            # Strip XML tags for text searching
            clean_text = re.sub(r'<[^>]+>', ' ', content_xml)
            clean_text = re.sub(r'\s+', ' ', clean_text)  # Normalize whitespace
            
            # Keywords to check
            checks = {
                "client_name": "Elias Thorne" in clean_text,
                "spouse_name": "Clara Thorne" in clean_text,
                "child_marcus": "Marcus" in clean_text,
                "child_sophie": "Sophie" in clean_text,
                "guitar_bequest": "Gibson" in clean_text and "David" in clean_text,
                "watch_bequest": "Rolex" in clean_text and "Marcus" in clean_text,
                "guardianship_clause": "Appointment of Guardian" in clean_text or "APPOINTMENT OF GUARDIAN" in clean_text,
                "guardian_names": "Sarah and James Miller" in clean_text or "Sarah Miller" in clean_text
            }
            
            result["content_analysis"] = checks
            result["file_valid"] = True

    except Exception as e:
        result["error"] = str(e)

# Write result to file
with open("$RESULT_JSON", "w") as f:
    json.dump(result, f, indent=2)

PYEOF

# Fix permissions
chmod 666 "$RESULT_JSON" 2>/dev/null || sudo chmod 666 "$RESULT_JSON"

echo "Export complete. Result:"
cat "$RESULT_JSON"