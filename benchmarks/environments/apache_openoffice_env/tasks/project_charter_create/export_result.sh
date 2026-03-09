#!/bin/bash
set -e

echo "=== Exporting Project Charter Create Result ==="
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Take final screenshot
take_screenshot /tmp/task_final.png 2>/dev/null || true

# 2. Run Python analysis script
# This script inspects the ODT file structure without needing external heavy libraries
# It uses standard zipfile and regex to check for ODT XML elements
python3 << 'PYEOF'
import zipfile
import json
import os
import re
import time

OUTPUT_FILE = "/home/ga/Documents/Ridgeline_DC_Migration_Charter.odt"
RESULT_JSON = "/tmp/task_result.json"

result = {
    "file_exists": False,
    "file_size": 0,
    "timestamp_valid": False,
    "structure": {
        "has_toc": False,
        "h1_count": 0,
        "h2_count": 0,
        "table_count": 0,
        "has_footer_page_nums": False,
        "paragraph_count": 0
    },
    "content": {
        "has_company_name": False,
        "has_project_keywords": False,
        "has_budget_figure": False
    },
    "format": "unknown"
}

# Check file existence and metadata
if os.path.exists(OUTPUT_FILE):
    result["file_exists"] = True
    result["file_size"] = os.path.getsize(OUTPUT_FILE)
    
    # Check modification time against task start
    try:
        with open("/tmp/task_start_time.txt", "r") as f:
            start_time = int(f.read().strip())
        mtime = int(os.path.getmtime(OUTPUT_FILE))
        if mtime > start_time:
            result["timestamp_valid"] = True
    except:
        result["timestamp_valid"] = True # Default to true if timestamp read fails

    # Analyze ODT content
    try:
        with zipfile.ZipFile(OUTPUT_FILE, 'r') as z:
            # 1. content.xml analysis
            content = z.read('content.xml').decode('utf-8', errors='ignore')
            
            # Count Heading 1 (outline-level="1")
            # Look for <text:h ... text:outline-level="1">
            h1_matches = re.findall(r'<text:h[^>]*text:outline-level="1"', content)
            result["structure"]["h1_count"] = len(h1_matches)
            
            # Count Heading 2 (outline-level="2")
            h2_matches = re.findall(r'<text:h[^>]*text:outline-level="2"', content)
            result["structure"]["h2_count"] = len(h2_matches)
            
            # Count Tables (<table:table>)
            table_matches = re.findall(r'<table:table\b', content)
            result["structure"]["table_count"] = len(table_matches)
            
            # Check for Table of Contents (<text:table-of-content>)
            if 'text:table-of-content' in content:
                result["structure"]["has_toc"] = True
                
            # Count total paragraphs (proxy for length)
            paras = re.findall(r'<text:p\b', content)
            result["structure"]["paragraph_count"] = len(paras)
            
            # Text content analysis
            # Strip tags to get raw text for keyword search
            text_content = re.sub(r'<[^>]+>', ' ', content)
            text_content_lower = text_content.lower()
            
            if "ridgeline" in text_content_lower:
                result["content"]["has_company_name"] = True
                
            if any(x in text_content_lower for x in ["migration", "aws", "data center", "markley"]):
                result["content"]["has_project_keywords"] = True
                
            if any(x in text_content for x in ["4,200,000", "4.2M", "$4.2", "1,680,000"]):
                result["content"]["has_budget_figure"] = True

            # 2. styles.xml analysis (for footer/page numbers)
            if 'styles.xml' in z.namelist():
                styles = z.read('styles.xml').decode('utf-8', errors='ignore')
                # Check for footer style definition or page number field
                # Page numbers can be in styles.xml (master page) or content.xml
                has_pn_styles = 'text:page-number' in styles
                has_pn_content = 'text:page-number' in content
                if has_pn_styles or has_pn_content:
                    result["structure"]["has_footer_page_nums"] = True

            result["format"] = "odt"

    except zipfile.BadZipFile:
        result["format"] = "corrupt_zip"
    except Exception as e:
        result["error"] = str(e)

# Write result
with open(RESULT_JSON, 'w') as f:
    json.dump(result, f, indent=2)

print(f"Analysis complete. JSON saved to {RESULT_JSON}")
PYEOF

# 3. Permissions fix
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="