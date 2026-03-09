#!/bin/bash
echo "=== Exporting Construction Bid Proposal Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Define output path
OUTPUT_FILE="/home/ga/Documents/Ironclad_Bid_Proposal_LSCU.odt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Python script to analyze the ODT file
# We use Python to parse the zipped XML within the ODT file
python3 << 'PYEOF'
import zipfile
import json
import os
import re
import sys
import datetime

output_file = "/home/ga/Documents/Ironclad_Bid_Proposal_LSCU.odt"
task_start = int(sys.argv[1]) if len(sys.argv) > 1 else 0

result = {
    "file_exists": False,
    "file_size": 0,
    "file_created_during_task": False,
    "structure": {
        "heading1_count": 0,
        "heading2_count": 0,
        "has_toc": False,
        "has_footer": False,
        "has_page_numbers": False,
        "table_count": 0,
        "paragraph_count": 0
    },
    "content": {
        "has_company_name": False,
        "has_client_name": False,
        "has_bid_amount": False,
        "has_cost_table_terms": False
    },
    "export_timestamp": datetime.datetime.now().isoformat()
}

if os.path.exists(output_file):
    result["file_exists"] = True
    result["file_size"] = os.path.getsize(output_file)
    
    # Check modification time
    mtime = os.path.getmtime(output_file)
    if mtime > task_start:
        result["file_created_during_task"] = True

    try:
        with zipfile.ZipFile(output_file, 'r') as zf:
            # Read content.xml
            content_xml = zf.read('content.xml').decode('utf-8', errors='replace')
            
            # Read styles.xml (for footer/page numbers sometimes)
            styles_xml = ""
            if 'styles.xml' in zf.namelist():
                styles_xml = zf.read('styles.xml').decode('utf-8', errors='replace')

            # --- Structural Analysis ---
            
            # Count Heading 1 (outline-level="1")
            result["structure"]["heading1_count"] = len(re.findall(r'text:outline-level="1"', content_xml))
            
            # Count Heading 2 (outline-level="2")
            result["structure"]["heading2_count"] = len(re.findall(r'text:outline-level="2"', content_xml))
            
            # Check for Table of Contents
            result["structure"]["has_toc"] = 'text:table-of-content' in content_xml
            
            # Check for Tables
            result["structure"]["table_count"] = len(re.findall(r'<table:table ', content_xml))
            
            # Count paragraphs (rough proxy for content volume)
            result["structure"]["paragraph_count"] = len(re.findall(r'<text:p', content_xml))
            
            # Check for Page Numbers (text:page-number)
            # Can be in content.xml or styles.xml (footer styles)
            has_pn_content = 'text:page-number' in content_xml
            has_pn_styles = 'text:page-number' in styles_xml
            result["structure"]["has_page_numbers"] = has_pn_content or has_pn_styles
            
            # Check for Footer style
            result["structure"]["has_footer"] = '<style:footer' in styles_xml
            
            # --- Content Analysis ---
            
            # Extract plain text for searching
            full_text = re.sub(r'<[^>]+>', ' ', content_xml).lower()
            
            # Check specific terms
            result["content"]["has_company_name"] = "ironclad" in full_text
            result["content"]["has_client_name"] = "lone star" in full_text
            
            # Check bid amount (1,009,000 or 1009000)
            result["content"]["has_bid_amount"] = "1,009,000" in full_text or "1009000" in full_text or "1 009 000" in full_text
            
            # Check for cost table terms (Division, Amount, Total)
            result["content"]["has_cost_table_terms"] = ("division" in full_text and "amount" in full_text)

    except Exception as e:
        result["error"] = str(e)

# Write result to temp file
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF
"$TASK_START"

# 4. Handle permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="