#!/bin/bash
echo "=== Exporting Physics Test Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

OUTPUT_FILE="/home/ga/Documents/Physics_Unit3_Exam.odt"
RESULT_JSON="/tmp/task_result.json"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Use Python to analyze the ODT structure (it's a zip file)
python3 << 'PYEOF'
import zipfile
import json
import os
import re
import sys

output_path = "/home/ga/Documents/Physics_Unit3_Exam.odt"
result = {
    "file_exists": False,
    "formula_count": 0,
    "image_count": 0,
    "text_content_found": [],
    "margins_correct": False,
    "file_size": 0,
    "is_valid_odt": False
}

if os.path.exists(output_path):
    result["file_exists"] = True
    result["file_size"] = os.path.getsize(output_path)
    
    try:
        if zipfile.is_zipfile(output_path):
            result["is_valid_odt"] = True
            with zipfile.ZipFile(output_path, 'r') as z:
                # 1. Check for Formulas (Object directories or manifest entries)
                # OpenOffice formulas usually live in "Object X/" folders or are referenced in manifest
                namelist = z.namelist()
                
                # Method A: Count "Object" directories containing content.xml (typical for embedded objects)
                # Note: ODT embedded objects often have paths like 'Object 1/content.xml'
                object_dirs = set()
                for name in namelist:
                    if re.match(r'Object \d+/content.xml', name):
                        object_dirs.add(name.split('/')[0])
                
                # Check manifest for explicit formula mime-type to be sure
                # application/vnd.oasis.opendocument.formula
                formula_mime_count = 0
                try:
                    manifest = z.read('META-INF/manifest.xml').decode('utf-8')
                    formula_mime_count = manifest.count('application/vnd.oasis.opendocument.formula')
                except:
                    pass
                
                # Use the higher count (directory structure vs manifest)
                result["formula_count"] = max(len(object_dirs), formula_mime_count)

                # 2. Check for Images
                # Images usually in Pictures/ directory
                image_files = [n for n in namelist if n.startswith('Pictures/') and len(n) > 9]
                result["image_count"] = len(image_files)

                # 3. Analyze Content Text
                content_xml = z.read('content.xml').decode('utf-8')
                
                required_strings = [
                    "Westview Academy",
                    "Physics 301",
                    "Work and Energy",
                    "Name:",
                    "Kinetic Energy"
                ]
                
                found_strings = []
                for s in required_strings:
                    if s in content_xml: # simple check, might need to strip tags if split across tags
                        found_strings.append(s)
                    else:
                        # deeper check ignoring tags
                        clean_text = re.sub(r'<[^>]+>', '', content_xml)
                        if s in clean_text:
                            found_strings.append(s)
                
                result["text_content_found"] = found_strings

                # 4. Check Margins (Styles.xml)
                # Look for margin properties. 0.75in is approx 1.905cm
                # Standard styles usually named "Standard" or "Default Style"
                try:
                    styles_xml = z.read('styles.xml').decode('utf-8')
                    # Look for page-layout-properties
                    # fo:margin-top="0.75in" or "1.905cm" or similar
                    # We check loosely for the value presence in the styles
                    if '0.75in' in styles_xml or '1.9cm' in styles_xml or '1.91cm' in styles_xml or '1.905cm' in styles_xml:
                        result["margins_correct"] = True
                except:
                    pass

    except Exception as e:
        result["error"] = str(e)

# Write result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)
PYEOF

# Move result to safe location and set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true
cat /tmp/task_result.json
echo "=== Export Complete ==="