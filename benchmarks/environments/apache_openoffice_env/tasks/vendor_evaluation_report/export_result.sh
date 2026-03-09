#!/bin/bash
echo "=== Exporting Vendor Evaluation Report Result ==="

# Source shared utilities if available
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Define output path
OUTPUT_FILE="/home/ga/Documents/Avalon_Vendor_Eval_2025.odt"

# 3. Python script to parse ODT and analyze content
python3 << 'PYEOF'
import json
import os
import zipfile
import re
import sys
import time

output_file = "/home/ga/Documents/Avalon_Vendor_Eval_2025.odt"
task_start_file = "/tmp/task_start_time.txt"

# Default result structure
result = {
    "file_exists": False,
    "file_size": 0,
    "created_during_task": False,
    "heading1_count": 0,
    "heading2_count": 0,
    "table_count": 0,
    "paragraph_count": 0,
    "has_toc": False,
    "has_footer_pagenum": False,
    "vendors_found": [],
    "quotes_found": [],
    "key_terms_found": [],
    "parse_error": None
}

# Check if file exists
if os.path.exists(output_file):
    result["file_exists"] = True
    result["file_size"] = os.path.getsize(output_file)
    
    # Check modification time against task start
    try:
        with open(task_start_file, 'r') as f:
            start_time = int(f.read().strip())
        file_mtime = int(os.path.getmtime(output_file))
        if file_mtime > start_time:
            result["created_during_task"] = True
    except Exception as e:
        result["parse_error"] = f"Timestamp check failed: {e}"

    # Parse ODT content
    try:
        with zipfile.ZipFile(output_file, 'r') as zf:
            # Read content.xml (Body text)
            content_xml = zf.read('content.xml').decode('utf-8', errors='ignore')
            
            # Read styles.xml (Footer/Header/Page layout)
            styles_xml = ""
            if 'styles.xml' in zf.namelist():
                styles_xml = zf.read('styles.xml').decode('utf-8', errors='ignore')

            # --- Structural Checks ---
            
            # Count Heading 1 (text:h with outline-level="1")
            result["heading1_count"] = len(re.findall(r'<text:h[^>]*text:outline-level="1"', content_xml))
            
            # Count Heading 2
            result["heading2_count"] = len(re.findall(r'<text:h[^>]*text:outline-level="2"', content_xml))
            
            # Count Tables
            result["table_count"] = len(re.findall(r'<table:table\b', content_xml))
            
            # Count Paragraphs
            result["paragraph_count"] = len(re.findall(r'<text:p\b', content_xml))
            
            # Check for Table of Contents
            if 'text:table-of-content' in content_xml:
                result["has_toc"] = True
                
            # Check for Page Numbers (in styles.xml or content.xml)
            if 'text:page-number' in styles_xml or 'text:page-number' in content_xml:
                result["has_footer_pagenum"] = True

            # --- Content Checks (extract raw text) ---
            # Simple regex to strip tags for text searching
            raw_text = re.sub(r'<[^>]+>', ' ', content_xml)
            raw_text_lower = raw_text.lower()
            
            # Check for Vendors
            vendors = [
                "Titanium Edge Tooling", "PrecisionCut International", 
                "Nordic Carbide Solutions", "Summit Tool & Die Works"
            ]
            for v in vendors:
                # Case insensitive check
                if v.lower() in raw_text_lower:
                    result["vendors_found"].append(v)
            
            # Check for Quotes (Numbers)
            # We look for the raw numbers (e.g. "587,400" or "587400")
            quotes = ["587,400", "542,800", "611,200", "498,600"]
            for q in quotes:
                clean_q = q.replace(",", "")
                if q in raw_text or clean_q in raw_text:
                    result["quotes_found"].append(q)
            
            # Check for Key Terms
            terms = ["Executive Summary", "Weighted Scoring", "Methodology", "Recommendation", "Compliance"]
            for t in terms:
                if t.lower() in raw_text_lower:
                    result["key_terms_found"].append(t)

    except Exception as e:
        result["parse_error"] = f"ODT Parse Failed: {str(e)}"

# Save result to JSON
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=4)

PYEOF

# 4. Handle permissions for the result file so host can read it
chmod 644 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="