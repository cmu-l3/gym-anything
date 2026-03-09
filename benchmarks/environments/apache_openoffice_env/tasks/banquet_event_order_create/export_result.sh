#!/bin/bash
# Export script for Banquet Event Order task

echo "=== Exporting Banquet Event Order Result ==="
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png 2>/dev/null || true

# 2. Analyze the output file
OUTPUT_FILE="/home/ga/Documents/BEO_MillerTech_Retreat.odt"
RESULT_JSON="/tmp/task_result.json"

# Use Python to inspect the ODT structure and content
python3 << 'PYEOF'
import json
import os
import zipfile
import re
import datetime

output_file = "/home/ga/Documents/BEO_MillerTech_Retreat.odt"
result = {
    "file_exists": False,
    "file_size": 0,
    "table_count": 0,
    "has_header_info": False,
    "has_footer": False,
    "content_check": {
        "client_name": False,
        "beo_number": False,
        "date": False,
        "menu_item_1": False, # Smoked Salmon
        "menu_item_2": False, # Chia Parfaits
        "av_item_1": False,   # Wireless Lav
        "av_item_2": False    # 4K Projector
    },
    "timestamp": datetime.datetime.now().isoformat()
}

if os.path.exists(output_file):
    result["file_exists"] = True
    result["file_size"] = os.path.getsize(output_file)
    
    try:
        with zipfile.ZipFile(output_file, 'r') as z:
            # Read Content
            content_xml = z.read('content.xml').decode('utf-8', errors='replace')
            styles_xml = z.read('styles.xml').decode('utf-8', errors='replace')
            
            # Combine text for searching
            full_text = re.sub(r'<[^>]+>', ' ', content_xml).lower()
            
            # check table count
            result["table_count"] = content_xml.count('<table:table ')
            
            # Check content presence
            result["content_check"]["client_name"] = "miller-tech" in full_text
            result["content_check"]["beo_number"] = "beo-24-992" in full_text
            result["content_check"]["date"] = "october 12, 2025" in full_text or "oct 12" in full_text
            result["content_check"]["menu_item_1"] = "smoked salmon" in full_text
            result["content_check"]["menu_item_2"] = "chia parfait" in full_text
            result["content_check"]["av_item_1"] = "wireless lav" in full_text
            result["content_check"]["av_item_2"] = "4k projector" in full_text
            
            # Check Header/Footer presence in styles.xml or content
            # ODT headers/footers are often in styles.xml master-page definitions
            has_footer_style = '<style:footer' in styles_xml
            has_page_num = 'text:page-number' in styles_xml or 'text:page-number' in content_xml
            has_internal_dist = "internal distribution" in full_text or "internal distribution" in re.sub(r'<[^>]+>', ' ', styles_xml).lower()
            
            result["has_footer"] = has_footer_style and (has_page_num or has_internal_dist)
            
            # Check if header info is roughly at the top (heuristic)
            # We assume if it's in the file, and file has content, it's likely correctly placed if we find it
            result["has_header_info"] = result["content_check"]["beo_number"] and result["content_check"]["date"]

    except Exception as e:
        result["error"] = str(e)

# Write result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

# 3. Secure the result file
chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="