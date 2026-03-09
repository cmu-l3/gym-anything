#!/bin/bash
# Export script for exhibit_catalog_create task

echo "=== Exporting Exhibition Catalog Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Define Output Path
OUTPUT_FILE="/home/ga/Documents/Light_in_Motion_Catalog.odt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Analyze ODT file using Python
# We extract metadata, styles, and content to verify the requirements
python3 << 'PYEOF'
import zipfile
import json
import os
import re
import datetime

output_file = "/home/ga/Documents/Light_in_Motion_Catalog.odt"
task_start = int(os.environ.get('TASK_START', 0))

result = {
    "file_exists": False,
    "file_size_bytes": 0,
    "file_created_during_task": False,
    "h1_count": 0,
    "h2_count": 0,
    "has_toc": False,
    "has_page_numbers": False,
    "has_table": False,
    "paragraph_count": 0,
    "artists_found": [],
    "terms_found": [],
    "export_timestamp": datetime.datetime.now().isoformat()
}

if os.path.exists(output_file):
    result["file_exists"] = True
    result["file_size_bytes"] = os.path.getsize(output_file)
    
    # Check modification time
    mtime = int(os.path.getmtime(output_file))
    if mtime > task_start:
        result["file_created_during_task"] = True

    try:
        with zipfile.ZipFile(output_file, 'r') as zf:
            # Parse content.xml
            content_xml = zf.read('content.xml').decode('utf-8', errors='replace')
            
            # Count Heading 1 (outline-level="1")
            # Note: OpenOffice uses text:outline-level attribute on text:h elements
            h1_matches = re.findall(r'<text:h[^>]*text:outline-level="1"', content_xml)
            result["h1_count"] = len(h1_matches)
            
            # Count Heading 2 (outline-level="2")
            h2_matches = re.findall(r'<text:h[^>]*text:outline-level="2"', content_xml)
            result["h2_count"] = len(h2_matches)
            
            # Check for Table of Contents
            if '<text:table-of-content' in content_xml:
                result["has_toc"] = True
                
            # Check for Tables (Inventory Checklist)
            if '<table:table' in content_xml:
                result["has_table"] = True
                
            # Count paragraphs (rough length check)
            paras = re.findall(r'<text:p\b', content_xml)
            result["paragraph_count"] = len(paras)
            
            # Text Content Analysis
            # Remove XML tags to search plain text
            plain_text = re.sub(r'<[^>]+>', ' ', content_xml).lower()
            
            # Check for Artists
            artists = ["monet", "renoir", "degas", "morisot", "caillebotte", "cassatt", "pissarro", "sisley"]
            found_artists = [a for a in artists if a in plain_text]
            result["artists_found"] = found_artists
            
            # Check for Key Terms
            terms = ["impression", "oil on canvas", "catalog", "catalogue"]
            found_terms = [t for t in terms if t in plain_text]
            result["terms_found"] = found_terms

            # Parse styles.xml for Footer/Page Numbers
            # Page numbers can be in styles.xml (master page) or content.xml
            styles_xml = ""
            if 'styles.xml' in zf.namelist():
                styles_xml = zf.read('styles.xml').decode('utf-8', errors='replace')
            
            if 'text:page-number' in styles_xml or 'text:page-number' in content_xml:
                result["has_page_numbers"] = True

    except Exception as e:
        result["error"] = str(e)

# Save result to JSON
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

# 4. Handle permissions for the result file
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="