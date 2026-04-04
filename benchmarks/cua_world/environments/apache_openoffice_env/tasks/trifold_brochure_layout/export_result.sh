#!/bin/bash
echo "=== Exporting Tri-fold Brochure Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

OUTPUT_FILE="/home/ga/Documents/wellness_expo_brochure.odt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Use Python to analyze the ODT structure directly
# We extract data to JSON for the verifier
python3 << PYEOF
import zipfile
import json
import os
import re
import sys

output_path = "$OUTPUT_FILE"
result = {
    "file_exists": False,
    "file_size": 0,
    "is_landscape": False,
    "column_count": 0,
    "images_count": 0,
    "content_found": [],
    "xml_parse_error": None
}

if os.path.exists(output_path):
    result["file_exists"] = True
    result["file_size"] = os.path.getsize(output_path)
    
    try:
        with zipfile.ZipFile(output_path, 'r') as zf:
            # 1. Check Images (count files in Pictures/ directory inside ODT)
            image_files = [f for f in zf.namelist() if f.startswith('Pictures/')]
            result["images_count"] = len(image_files)

            # 2. Analyze styles.xml for Page Layout (Orientation & Columns)
            styles_xml = zf.read('styles.xml').decode('utf-8', errors='replace')
            
            # Check Orientation
            # OpenOffice usually sets print-orientation="landscape" OR sets width > height
            if 'style:print-orientation="landscape"' in styles_xml:
                result["is_landscape"] = True
            else:
                # Fallback: Check page dimensions
                # format: svg:width="11in" svg:height="8.5in"
                width_match = re.search(r'fo:page-width="([\d\.]+)(\w+)"', styles_xml)
                height_match = re.search(r'fo:page-height="([\d\.]+)(\w+)"', styles_xml)
                if width_match and height_match:
                    w_val, w_unit = float(width_match.group(1)), width_match.group(2)
                    h_val, h_unit = float(height_match.group(1)), height_match.group(2)
                    if w_unit == h_unit and w_val > h_val:
                        result["is_landscape"] = True

            # Check Columns
            # Look for <style:columns fo:column-count="3">
            col_match = re.search(r'fo:column-count="(\d+)"', styles_xml)
            if col_match:
                result["column_count"] = int(col_match.group(1))

            # 3. Analyze content.xml for Text
            content_xml = zf.read('content.xml').decode('utf-8', errors='replace')
            plain_text = re.sub(r'<[^>]+>', ' ', content_xml)
            
            check_strings = [
                "Spring 2026 Wellness Expo",
                "Mercy General Health System", 
                "Healthy Cooking Demonstration",
                "outreach@mercygeneral.org"
            ]
            
            for s in check_strings:
                if s in plain_text:
                    result["content_found"].append(s)

    except Exception as e:
        result["xml_parse_error"] = str(e)

# Save result to file
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)

print(f"Export analysis complete. File exists: {result['file_exists']}")
PYEOF

# Set permissions so ga user or verifier can read it
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="