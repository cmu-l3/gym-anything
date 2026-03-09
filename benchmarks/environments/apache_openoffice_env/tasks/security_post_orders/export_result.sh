#!/bin/bash
# Export script for Security Post Orders task
echo "=== Exporting Security Post Orders Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot of the state
take_screenshot /tmp/task_final.png 2>/dev/null || true

OUTPUT_FILE="/home/ga/Documents/SPO-HBC-2024-003.odt"
RESULT_FILE="/tmp/task_result.json"
START_TIME=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Use Python to analyze the ODT file structure deeply
python3 << PYEOF
import json
import os
import zipfile
import re
import datetime

output_file = "$OUTPUT_FILE"
start_time = int("$START_TIME")
result = {
    "file_exists": False,
    "file_size": 0,
    "file_created_during_task": False,
    "heading1_count": 0,
    "heading2_count": 0,
    "table_count": 0,
    "has_toc": False,
    "has_footer": False,
    "has_page_numbers": False,
    "paragraph_count": 0,
    "company_names_present": False,
    "keywords_present": False,
    "parse_error": None,
    "timestamp": datetime.datetime.now().isoformat()
}

if not os.path.exists(output_file):
    print("Output file not found.")
    with open("$RESULT_FILE", "w") as f:
        json.dump(result, f)
    exit(0)

# File stats
stat = os.stat(output_file)
result["file_exists"] = True
result["file_size"] = stat.st_size
# Check modification time against task start time
result["file_created_during_task"] = stat.st_mtime > start_time

try:
    with zipfile.ZipFile(output_file, 'r') as z:
        # 1. Analyze content.xml
        with z.open('content.xml') as cf:
            content = cf.read().decode('utf-8', errors='replace')
        
        # Count Headings (styles)
        # Look for text:h with outline-level="1" or "2"
        h1_matches = re.findall(r'<text:h[^>]+text:outline-level="1"', content)
        h2_matches = re.findall(r'<text:h[^>]+text:outline-level="2"', content)
        result["heading1_count"] = len(h1_matches)
        result["heading2_count"] = len(h2_matches)
        
        # Count Tables
        table_matches = re.findall(r'<table:table\b', content)
        result["table_count"] = len(table_matches)
        
        # Check for TOC
        result["has_toc"] = 'text:table-of-content' in content
        
        # Count Paragraphs
        para_matches = re.findall(r'<text:p\b', content)
        result["paragraph_count"] = len(para_matches)
        
        # Check text content
        plain_text = re.sub(r'<[^>]+>', ' ', content).lower()
        
        # Check for company names
        has_sentinel = "sentinel shield" in plain_text
        has_helios = "helios" in plain_text
        result["company_names_present"] = has_sentinel and has_helios
        
        # Check for security keywords
        keywords = ["post orders", "patrol", "access control", "emergency"]
        found_keywords = [k for k in keywords if k in plain_text]
        result["keywords_present"] = len(found_keywords) >= 3
        
        # Check for page numbers in content (sometimes placed directly)
        page_num_in_content = 'text:page-number' in content
        
        # 2. Analyze styles.xml (often holds footer definitions)
        with z.open('styles.xml') as sf:
            styles = sf.read().decode('utf-8', errors='replace')
        
        result["has_footer"] = '<style:footer' in styles or '<text:footer' in styles
        
        # Page numbers can be in styles (footer) or content
        result["has_page_numbers"] = page_num_in_content or ('text:page-number' in styles)

except Exception as e:
    result["parse_error"] = str(e)
    print(f"Error parsing ODT: {e}")

# Save result
with open("$RESULT_FILE", "w") as f:
    json.dump(result, f, indent=2)

print("Analysis complete.")
PYEOF

# Ensure permissions
chmod 666 "$RESULT_FILE" 2>/dev/null || true

echo "=== Export Complete ==="
cat "$RESULT_FILE"