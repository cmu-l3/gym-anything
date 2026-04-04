#!/bin/bash
# Export script for fire_safety_inspection_report
set -e

echo "=== Exporting Fire Safety Inspection Report Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check output file
OUTPUT_FILE="/home/ga/Documents/FSI_Report_Glenwood_2024.odt"
RESULT_JSON="/tmp/task_result.json"

# 3. Python script to unzip ODT and parse XML for verification
# This runs inside the environment to avoid dependency issues on host
python3 << 'PYEOF'
import json
import os
import zipfile
import re
import datetime

output_file = "/home/ga/Documents/FSI_Report_Glenwood_2024.odt"
result = {
    "file_exists": False,
    "file_size": 0,
    "heading1_count": 0,
    "heading2_count": 0,
    "table_count": 0,
    "paragraph_count": 0,
    "has_toc": False,
    "has_footer": False,
    "has_page_numbers": False,
    "text_content_check": {
        "building_names_found": 0,
        "nfpa_terms_found": False,
        "scores_found": 0
    },
    "timestamp": datetime.datetime.now().isoformat()
}

if os.path.exists(output_file):
    result["file_exists"] = True
    result["file_size"] = os.path.getsize(output_file)
    
    try:
        with zipfile.ZipFile(output_file, 'r') as zf:
            # Read content.xml (main body)
            content = zf.read('content.xml').decode('utf-8', errors='replace')
            
            # Count Heading 1 (proper styles)
            h1_matches = re.findall(r'<text:h[^>]*text:outline-level="1"', content)
            result["heading1_count"] = len(h1_matches)
            
            # Count Heading 2 (proper styles)
            h2_matches = re.findall(r'<text:h[^>]*text:outline-level="2"', content)
            result["heading2_count"] = len(h2_matches)
            
            # Count Tables
            table_matches = re.findall(r'<table:table\b', content)
            result["table_count"] = len(table_matches)
            
            # Count Paragraphs (approximate body text)
            # text:p and text:h are both paragraph-level
            para_matches = re.findall(r'<text:p\b', content)
            result["paragraph_count"] = len(para_matches)
            
            # Check for Table of Contents
            result["has_toc"] = 'text:table-of-content' in content
            
            # Read styles.xml (footer/header defs)
            styles = ""
            if 'styles.xml' in zf.namelist():
                styles = zf.read('styles.xml').decode('utf-8', errors='replace')
            
            # Check for Footer/Page Numbers
            # Page numbers can be in styles (footer) or content (direct)
            result["has_footer"] = '<style:footer' in styles or '<text:footer' in styles
            result["has_page_numbers"] = ('text:page-number' in styles or 'text:page-number' in content)
            
            # Text Content Verification
            # Extract plain text roughly
            plain_text = re.sub(r'<[^>]+>', ' ', content).lower()
            
            # Building Names
            buildings = ["Main Academic Hall", "Science", "Student Services", "Performing Arts", "Physical Plant"]
            b_count = sum(1 for b in buildings if b.lower() in plain_text)
            result["text_content_check"]["building_names_found"] = b_count
            
            # NFPA Terms
            result["text_content_check"]["nfpa_terms_found"] = ("nfpa" in plain_text) and ("violation" in plain_text or "corrective action" in plain_text)
            
            # Scores
            scores = ["78", "82", "91", "76", "64"]
            s_count = sum(1 for s in scores if s in plain_text)
            result["text_content_check"]["scores_found"] = s_count
            
    except Exception as e:
        result["error"] = str(e)

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(f"Export analysis complete. File size: {result['file_size']}")
PYEOF

# 4. Handle permissions for the result file so verifier can read it
chmod 644 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="