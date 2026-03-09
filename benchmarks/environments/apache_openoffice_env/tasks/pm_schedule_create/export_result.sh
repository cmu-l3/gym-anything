#!/bin/bash
# export_result.sh for pm_schedule_create

echo "=== Exporting PM Schedule Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
take_screenshot /tmp/task_final.png

# Path to the expected output file
OUTPUT_FILE="/home/ga/Documents/CRWA_PM_Schedule_FY2025.odt"
RESULT_JSON="/tmp/task_result.json"

# Python script to analyze the ODT file structure
python3 << 'PYEOF'
import zipfile
import json
import os
import re
import datetime

output_file = "/home/ga/Documents/CRWA_PM_Schedule_FY2025.odt"
result_path = "/tmp/task_result.json"

result = {
    "file_exists": False,
    "file_size": 0,
    "heading1_count": 0,
    "heading2_count": 0,
    "has_toc": False,
    "has_page_numbers": False,
    "table_count": 0,
    "paragraph_count": 0,
    "text_content_check": {
        "plant_name": False,
        "pm_terms": False,
        "equipment_mentioned": False
    },
    "export_timestamp": datetime.datetime.now().isoformat(),
    "parse_error": None
}

if os.path.exists(output_file):
    result["file_exists"] = True
    result["file_size"] = os.path.getsize(output_file)
    
    try:
        if zipfile.is_zipfile(output_file):
            with zipfile.ZipFile(output_file, 'r') as zf:
                # Read content.xml
                content = zf.read('content.xml').decode('utf-8', errors='replace')
                
                # Check for Heading 1 (outline-level="1")
                # Regex looks for <text:h ... outline-level="1" ... >
                h1_matches = re.findall(r'<text:h\b[^>]*text:outline-level="1"', content)
                result["heading1_count"] = len(h1_matches)
                
                # Check for Heading 2 (outline-level="2")
                h2_matches = re.findall(r'<text:h\b[^>]*text:outline-level="2"', content)
                result["heading2_count"] = len(h2_matches)
                
                # Check for Tables (<table:table ...>)
                table_matches = re.findall(r'<table:table\b', content)
                result["table_count"] = len(table_matches)
                
                # Check for Table of Contents (<text:table-of-content ...>)
                result["has_toc"] = 'text:table-of-content' in content
                
                # Check for Paragraphs (rough count of non-empty paragraphs)
                result["paragraph_count"] = len(re.findall(r'<text:p\b', content))
                
                # Extract text for content check
                plain_text = re.sub(r'<[^>]+>', ' ', content).lower()
                
                result["text_content_check"]["plant_name"] = ("clearwater" in plain_text or "long creek" in plain_text)
                result["text_content_check"]["pm_terms"] = ("preventive maintenance" in plain_text or "pm schedule" in plain_text)
                result["text_content_check"]["equipment_mentioned"] = ("pump" in plain_text or "generator" in plain_text)
                
                # Read styles.xml for footer page numbers
                if 'styles.xml' in zf.namelist():
                    styles = zf.read('styles.xml').decode('utf-8', errors='replace')
                    # Page number usually appears as <text:page-number .../> inside a footer style
                    # It can also be in content.xml if directly inserted
                    result["has_page_numbers"] = ('text:page-number' in styles or 'text:page-number' in content)
                    
        else:
            result["parse_error"] = "File is not a valid ODT zip archive"
            
    except Exception as e:
        result["parse_error"] = str(e)

# Write result to JSON
with open(result_path, 'w') as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

# Ensure permissions
chmod 666 "$RESULT_JSON" 2>/dev/null || true

echo "=== Export complete ==="