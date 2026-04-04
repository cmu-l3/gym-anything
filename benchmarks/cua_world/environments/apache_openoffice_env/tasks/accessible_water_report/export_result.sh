#!/bin/bash
echo "=== Exporting Accessible Water Report Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Define Output Paths
OUTPUT_FILE="/home/ga/Documents/Oakwood_CCR_2024.odt"
RESULT_JSON="/tmp/task_result.json"
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Analyze ODT File Structure (using Python)
# We need to unzip the ODT (which is a zip) and parse content.xml and meta.xml
# to verify accessibility features that aren't visible in plain text.

python3 << PY_SCRIPT
import zipfile
import json
import os
import re
import sys
from xml.dom import minidom

output_file = "$OUTPUT_FILE"
task_start = int("$TASK_START_TIME")
result = {
    "file_exists": False,
    "file_size": 0,
    "created_after_start": False,
    "has_heading1": False,
    "has_heading2": False,
    "has_image": False,
    "alt_text_correct": False,
    "alt_text_found": None,
    "has_table": False,
    "has_header_row": False,
    "title_metadata_correct": False,
    "title_found": None,
    "content_check": False
}

if os.path.exists(output_file):
    result["file_exists"] = True
    stat = os.stat(output_file)
    result["file_size"] = stat.st_size
    if stat.st_mtime > task_start:
        result["created_after_start"] = True

    try:
        with zipfile.ZipFile(output_file, 'r') as z:
            # --- Check content.xml ---
            content_xml = z.read('content.xml').decode('utf-8')
            
            # Check Headings (looking for outline-level="1" and "2")
            # OpenOffice styles: <text:h text:style-name="Heading_20_1" text:outline-level="1">
            if 'text:outline-level="1"' in content_xml:
                result["has_heading1"] = True
            if 'text:outline-level="2"' in content_xml:
                result["has_heading2"] = True
                
            # Check Image and Alt Text
            # Image is usually in <draw:frame> ... <draw:image> ... <svg:desc>Alt Text</svg:desc> ... </draw:frame>
            # OR <svg:title> or <svg:desc> inside the frame.
            if '<draw:image' in content_xml:
                result["has_image"] = True
                
            # Regex to find description. Note: XML namespaces may vary slightly, usually svg:desc
            desc_match = re.search(r'<svg:desc[^>]*>(.*?)</svg:desc>', content_xml)
            if desc_match:
                found_alt = desc_match.group(1)
                result["alt_text_found"] = found_alt
                expected_alt = "Annual pH levels showing stability between 7.2 and 7.4"
                # Normalize spaces
                if " ".join(found_alt.split()) == expected_alt:
                    result["alt_text_correct"] = True
            
            # Check Table Header Rows
            # Looking for <table:table-header-rows>
            if '<table:table-header-rows>' in content_xml:
                result["has_header_row"] = True
                
            if '<table:table' in content_xml:
                result["has_table"] = True
                
            # Basic Content Check (Chlorine data)
            if "Chlorine" in content_xml and "0.8 ppm" in content_xml:
                result["content_check"] = True

            # --- Check meta.xml ---
            if 'meta.xml' in z.namelist():
                meta_xml = z.read('meta.xml').decode('utf-8')
                # <dc:title>2024 Water Quality Report</dc:title>
                title_match = re.search(r'<dc:title>(.*?)</dc:title>', meta_xml)
                if title_match:
                    found_title = title_match.group(1)
                    result["title_found"] = found_title
                    if found_title == "2024 Water Quality Report":
                        result["title_metadata_correct"] = True

    except Exception as e:
        result["error"] = str(e)

# Write result to JSON
with open("$RESULT_JSON", "w") as f:
    json.dump(result, f, indent=2)

PY_SCRIPT

# 4. Permissions fix
chmod 666 "$RESULT_JSON" 2>/dev/null || true

echo "Analysis complete. Result saved to $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export Complete ==="