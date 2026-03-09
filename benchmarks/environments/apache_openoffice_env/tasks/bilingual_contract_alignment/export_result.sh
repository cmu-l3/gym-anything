#!/bin/bash
set -e

echo "=== Exporting Bilingual Contract Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
take_screenshot /tmp/task_final.png 2>/dev/null || true

# Path to output
OUTPUT_FILE="/home/ga/Documents/GlobalTech_Schmidt_Agreement.odt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Run python script to analyze the ODT file structure
python3 << 'PYEOF'
import zipfile
import json
import os
import re
import sys
from xml.dom.minidom import parseString

output_file = "/home/ga/Documents/GlobalTech_Schmidt_Agreement.odt"
task_start = int(os.environ.get("TASK_START", 0))

result = {
    "file_exists": False,
    "file_created_during_task": False,
    "file_size": 0,
    "has_table": False,
    "table_columns": 0,
    "row_alignment_score": 0, # Percentage of rows with 2 cells
    "content_found": [],
    "has_header": False,
    "has_page_numbers": False,
    "borders_hidden": False
}

if os.path.exists(output_file):
    result["file_exists"] = True
    stats = os.stat(output_file)
    result["file_size"] = stats.st_size
    if stats.st_mtime > task_start:
        result["file_created_during_task"] = True

    try:
        with zipfile.ZipFile(output_file, 'r') as zf:
            # Parse content.xml
            content_xml = zf.read('content.xml').decode('utf-8', errors='replace')
            
            # Check for Table
            tables = re.findall(r'<table:table\b', content_xml)
            if tables:
                result["has_table"] = True
                
                # Check columns in first table
                # Naive regex check for column declarations
                cols = re.findall(r'<table:table-column\b', content_xml)
                result["table_columns"] = len(cols)
                
                # Check row structure (basic check)
                rows = re.findall(r'<table:table-row>(.*?)</table:table-row>', content_xml, re.DOTALL)
                valid_rows = 0
                for row in rows:
                    cells = re.findall(r'<table:table-cell\b', row)
                    if len(cells) >= 2:
                        valid_rows += 1
                
                if len(rows) > 0:
                    result["row_alignment_score"] = valid_rows / len(rows)

            # Check for Header text
            styles_xml = ""
            if 'styles.xml' in zf.namelist():
                styles_xml = zf.read('styles.xml').decode('utf-8', errors='replace')
            
            combined_xml = content_xml + styles_xml
            
            if "CONFIDENTIAL" in combined_xml and "VERTRAULICH" in combined_xml:
                result["has_header"] = True
                
            # Check for Page Numbers
            if "text:page-number" in combined_xml:
                result["has_page_numbers"] = True
                
            # Check for Hidden Borders
            # Look for table properties with border="none" or border-width="0"
            # This is tricky as it might be in styles.xml or automatic-styles in content.xml
            # We look for style definitions that apply to table cells/tables
            border_none = re.search(r'fo:border="none"', combined_xml)
            border_zero = re.search(r'fo:border="0\.00pt"', combined_xml)
            border_hidden = re.search(r'fo:border="hidden"', combined_xml)
            
            if border_none or border_zero or border_hidden:
                result["borders_hidden"] = True

            # Check content presence
            plain_text = re.sub(r'<[^>]+>', ' ', content_xml)
            check_phrases = ["Schmidt Engineering GmbH", "DACH region", "Force Majeure", "HÖHERE GEWALT"]
            for phrase in check_phrases:
                if phrase in plain_text:
                    result["content_found"].append(phrase)

    except Exception as e:
        result["error"] = str(e)

# Save result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="