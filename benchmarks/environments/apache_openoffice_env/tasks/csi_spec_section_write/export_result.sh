#!/bin/bash
# Export script for csi_spec_section_write task

echo "=== Exporting CSI Spec Section Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
take_screenshot /tmp/task_final.png

OUTPUT_FILE="/home/ga/Documents/093013_Ceramic_Tiling.odt"
RESULT_JSON="/tmp/task_result.json"

# Python script to parse ODT content
python3 << 'PYEOF'
import zipfile
import json
import os
import re
import datetime

output_file = "/home/ga/Documents/093013_Ceramic_Tiling.odt"
result_path = "/tmp/task_result.json"

result = {
    "file_exists": False,
    "file_size": 0,
    "parts_found": [],
    "heading1_count": 0,
    "heading2_count": 0,
    "table_count": 0,
    "has_header": False,
    "has_footer": False,
    "has_page_numbers": False,
    "content_check": {
        "ansi_a118": False,
        "tcna": False,
        "t1_found": False,
        "t2_found": False
    },
    "timestamp": datetime.datetime.now().isoformat()
}

if os.path.exists(output_file):
    result["file_exists"] = True
    result["file_size"] = os.path.getsize(output_file)
    
    try:
        with zipfile.ZipFile(output_file, 'r') as zf:
            # READ CONTENT.XML
            content = zf.read('content.xml').decode('utf-8', errors='replace')
            
            # Count Heading 1 (outline-level="1")
            # Note: OpenOffice usually uses text:h with outline-level
            h1_matches = re.findall(r'<text:h[^>]*text:outline-level="1"[^>]*>(.*?)</text:h>', content, re.DOTALL)
            result["heading1_count"] = len(h1_matches)
            
            # Check if PART 1, PART 2, PART 3 are in those headings
            for h_text in h1_matches:
                clean_text = re.sub(r'<[^>]+>', '', h_text).upper()
                if "PART 1" in clean_text: result["parts_found"].append("PART 1")
                if "PART 2" in clean_text: result["parts_found"].append("PART 2")
                if "PART 3" in clean_text: result["parts_found"].append("PART 3")
            
            # Count Heading 2
            h2_matches = re.findall(r'<text:h[^>]*text:outline-level="2"', content)
            result["heading2_count"] = len(h2_matches)
            
            # Count Tables
            table_matches = re.findall(r'<table:table\b', content)
            result["table_count"] = len(table_matches)
            
            # Content Keyword Checks (on plain text)
            plain_text = re.sub(r'<[^>]+>', ' ', content).lower()
            result["content_check"]["ansi_a118"] = "ansi a118" in plain_text
            result["content_check"]["tcna"] = "tcna" in plain_text
            result["content_check"]["t1_found"] = "t-1" in plain_text
            result["content_check"]["t2_found"] = "t-2" in plain_text
            
            # READ STYLES.XML (for header/footer)
            if 'styles.xml' in zf.namelist():
                styles = zf.read('styles.xml').decode('utf-8', errors='replace')
                
                # Check for header/footer definitions
                # <style:header> or <style:header-left> etc
                result["has_header"] = "style:header" in styles
                result["has_footer"] = "style:footer" in styles
                
                # Check for page number field
                # <text:page-number> usually appears in styles.xml for master page footers,
                # or content.xml if direct.
                result["has_page_numbers"] = "text:page-number" in styles or "text:page-number" in content

    except Exception as e:
        result["error"] = str(e)

with open(result_path, 'w') as f:
    json.dump(result, f, indent=2)

print(f"Exported result to {result_path}")
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "=== Export Complete ==="