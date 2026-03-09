#!/bin/bash
# Export script for landscape_maintenance_guide task

echo "=== Exporting Landscape Maintenance Guide Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record end time and take screenshot
date +%s > /tmp/task_end_time
take_screenshot /tmp/task_final.png

OUTPUT_FILE="/home/ga/Documents/Sullivan_Maintenance_Manual.odt"
RESULT_JSON="/tmp/task_result.json"

# Python script to parse ODT and analyze content
python3 << 'PYEOF'
import zipfile
import json
import os
import re
import datetime

output_file = "/home/ga/Documents/Sullivan_Maintenance_Manual.odt"
json_output = "/tmp/task_result.json"

result = {
    "file_exists": False,
    "file_size": 0,
    "has_toc": False,
    "has_page_numbers": False,
    "heading1_texts": [],
    "heading2_texts": [],
    "table_content": [],
    "full_text": "",
    "timestamp": datetime.datetime.now().isoformat()
}

if os.path.exists(output_file):
    result["file_exists"] = True
    result["file_size"] = os.path.getsize(output_file)
    
    try:
        with zipfile.ZipFile(output_file, 'r') as zf:
            # 1. Parse content.xml
            content_xml = zf.read('content.xml').decode('utf-8', errors='replace')
            
            # Check TOC
            result["has_toc"] = "text:table-of-content" in content_xml
            
            # Extract Headings (Heading 1 and Heading 2)
            # Regex looks for text:h elements with specific outline levels
            # Note: Content inside tags might be split, simpler regex to capture text content
            
            # Helper to strip tags
            def get_text(xml_snippet):
                return re.sub(r'<[^>]+>', '', xml_snippet)

            # Find all headings
            h1_matches = re.findall(r'<text:h[^>]*text:outline-level="1"[^>]*>(.*?)</text:h>', content_xml)
            result["heading1_texts"] = [get_text(h) for h in h1_matches]
            
            h2_matches = re.findall(r'<text:h[^>]*text:outline-level="2"[^>]*>(.*?)</text:h>', content_xml)
            result["heading2_texts"] = [get_text(h) for h in h2_matches]
            
            # Extract Table Data (simplified: just dumping all text inside table cells)
            table_matches = re.findall(r'<table:table-cell[^>]*>(.*?)</table:table-cell>', content_xml)
            result["table_content"] = [get_text(cell) for cell in table_matches]
            
            # Full text for keyword searching
            result["full_text"] = get_text(content_xml)
            
            # 2. Parse styles.xml for Footer/Page Numbers
            if 'styles.xml' in zf.namelist():
                styles_xml = zf.read('styles.xml').decode('utf-8', errors='replace')
                # Check for footer style definition or page number field
                # Page numbers can be in content.xml or styles.xml
                has_pn_styles = "text:page-number" in styles_xml
                has_pn_content = "text:page-number" in content_xml
                result["has_page_numbers"] = has_pn_styles or has_pn_content

    except Exception as e:
        result["error"] = str(e)

# Save result
with open(json_output, 'w') as f:
    json.dump(result, f, indent=2)

print(f"Analysis complete. File exists: {result['file_exists']}")
PYEOF

# Handle permissions
chmod 666 "$RESULT_JSON" 2>/dev/null || true

echo "=== Export Complete ==="
cat "$RESULT_JSON"