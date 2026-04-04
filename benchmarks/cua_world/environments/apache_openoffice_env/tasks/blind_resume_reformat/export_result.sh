#!/bin/bash
echo "=== Exporting Blind Resume Reformat Result ==="
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Define file paths
OUTPUT_FILE="/home/ga/Documents/Candidate_CRA-994_Blind.odt"
RESULT_JSON="/tmp/task_result.json"

# 3. Python script to analyze the ODT file
python3 << 'PYEOF'
import zipfile
import json
import os
import re

output_path = "/home/ga/Documents/Candidate_CRA-994_Blind.odt"
result = {
    "file_exists": False,
    "file_size": 0,
    "pii_found": [],
    "id_found": False,
    "footer_found": False,
    "table_found": False,
    "heading1_count": 0,
    "heading2_count": 0,
    "title_style_found": False
}

if os.path.exists(output_path):
    result["file_exists"] = True
    result["file_size"] = os.path.getsize(output_path)
    
    try:
        with zipfile.ZipFile(output_path, 'r') as zf:
            # Read content.xml
            content_xml = zf.read('content.xml').decode('utf-8', errors='ignore')
            
            # Read styles.xml (for footer definitions usually, but sometimes in content)
            if 'styles.xml' in zf.namelist():
                styles_xml = zf.read('styles.xml').decode('utf-8', errors='ignore')
            else:
                styles_xml = ""

            # 1. Check PII (Negative constraints)
            plain_text = re.sub(r'<[^>]+>', ' ', content_xml)
            forbidden = ["Marcus", "Reynolds", "415-555", "marcus.reynolds", "linkedin"]
            found_pii = []
            for term in forbidden:
                if term.lower() in plain_text.lower():
                    found_pii.append(term)
            result["pii_found"] = found_pii

            # 2. Check Candidate ID (Positive constraint)
            if "CRA-994" in plain_text:
                result["id_found"] = True

            # 3. Check Table
            if "<table:table" in content_xml:
                result["table_found"] = True

            # 4. Check Styles (Heading 1, Heading 2, Title)
            # Look for paragraphs with style names containing "Heading_20_1" etc.
            # ODT style names are often normalized, e.g. "Heading_20_1"
            h1_matches = re.findall(r'text:style-name="Heading_20_1"', content_xml)
            h2_matches = re.findall(r'text:style-name="Heading_20_2"', content_xml)
            title_matches = re.findall(r'text:style-name="Title"', content_xml)
            
            result["heading1_count"] = len(h1_matches)
            result["heading2_count"] = len(h2_matches)
            if len(title_matches) > 0:
                result["title_style_found"] = True

            # 5. Check Footer
            # Footer text might be in styles.xml (master page) or content.xml
            footer_text_sig = "Confidential Representation"
            if footer_text_sig in content_xml or footer_text_sig in styles_xml:
                result["footer_found"] = True

    except Exception as e:
        result["error"] = str(e)

# Save result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)

PYEOF

# 4. Handle permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result:"
cat /tmp/task_result.json