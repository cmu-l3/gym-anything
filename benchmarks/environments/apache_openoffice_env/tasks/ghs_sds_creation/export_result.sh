#!/bin/bash
echo "=== Exporting GHS SDS Creation Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task end info
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/Documents/SDS_ApexSolv5000.odt"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Run Python script to analyze the ODT file structure
# We use python3 with zipfile/xml parsing to be robust against missing odfpy
python3 << 'PYEOF'
import zipfile
import json
import os
import re
import sys
import time

output_path = "/home/ga/Documents/SDS_ApexSolv5000.odt"
result = {
    "file_exists": False,
    "file_size": 0,
    "valid_odt": False,
    "heading_count": 0,
    "table_count": 0,
    "cas_numbers_found": [],
    "hazard_text_found": False,
    "footer_found": False,
    "sections_found": [],
    "error": None
}

if os.path.exists(output_path):
    result["file_exists"] = True
    result["file_size"] = os.path.getsize(output_path)
    
    try:
        if zipfile.is_zipfile(output_path):
            with zipfile.ZipFile(output_path, 'r') as zf:
                # Check mimetype
                try:
                    mimetype = zf.read('mimetype').decode('utf-8')
                    if "application/vnd.oasis.opendocument.text" in mimetype:
                        result["valid_odt"] = True
                except:
                    pass # Continue anyway if valid zip
                
                # Parse content.xml
                content_xml = zf.read('content.xml').decode('utf-8', errors='ignore')
                
                # Check Heading 1 style usage
                # Look for <text:h text:outline-level="1">
                headings = re.findall(r'<text:h[^>]*text:outline-level="1"[^>]*>(.*?)</text:h>', content_xml)
                result["heading_count"] = len(headings)
                
                # Check for specific section headers (case insensitive)
                expected_sections = [str(i) for i in range(1, 17)]
                found_sections = []
                for h in headings:
                    clean_h = re.sub(r'<[^>]+>', '', h).lower() # Remove inner tags
                    for i in expected_sections:
                        if f"section {i}" in clean_h and i not in found_sections:
                            found_sections.append(i)
                result["sections_found"] = found_sections

                # Check Table existence
                tables = re.findall(r'<table:table\b', content_xml)
                result["table_count"] = len(tables)
                
                # Check text content
                plain_text = re.sub(r'<[^>]+>', ' ', content_xml)
                
                # Check CAS numbers
                target_cas = ["1310-73-2", "111-76-2", "6834-92-0"]
                found_cas = []
                for cas in target_cas:
                    if cas in plain_text:
                        found_cas.append(cas)
                result["cas_numbers_found"] = found_cas
                
                # Check Hazard Text
                if "H314" in plain_text or "Causes severe skin burns" in plain_text:
                    result["hazard_text_found"] = True
                    
                # Check Footer
                # Footers are usually in styles.xml, sometimes content.xml depending on config
                styles_xml = ""
                try:
                    styles_xml = zf.read('styles.xml').decode('utf-8', errors='ignore')
                except:
                    pass
                
                if "Revision Date" in plain_text or "Revision Date" in styles_xml:
                    result["footer_found"] = True
                if "<style:footer" in styles_xml or "<text:footer" in styles_xml:
                    # Also checking structural footer presence
                    pass

    except Exception as e:
        result["error"] = str(e)

# Save result to JSON
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=4)
PYEOF

# Set permissions for the result file
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
echo "=== Export Complete ==="