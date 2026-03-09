#!/bin/bash
echo "=== Exporting Child Welfare Case Plan Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Record end time and paths
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/Documents/Martinez_Family_Case_Plan.odt"

# 2. Capture final screenshot
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 3. Analyze the ODT file using Python inside the container
# We extract content.xml and styles.xml to verify formatting and content
echo "Analyzing ODT file..."
python3 << 'PYEOF'
import zipfile
import json
import os
import re
import sys

output_path = "/home/ga/Documents/Martinez_Family_Case_Plan.odt"
task_start = int(sys.argv[1]) if len(sys.argv) > 1 else 0

result = {
    "file_exists": False,
    "file_size_bytes": 0,
    "file_created_during_task": False,
    "heading1_count": 0,
    "heading2_count": 0,
    "table_count": 0,
    "has_toc": False,
    "has_page_numbers": False,
    "paragraph_count": 0,
    "keywords_found": [],
    "text_content_preview": ""
}

if os.path.exists(output_path):
    result["file_exists"] = True
    stat = os.stat(output_path)
    result["file_size_bytes"] = stat.st_size
    
    # Check modification time
    if stat.st_mtime > task_start:
        result["file_created_during_task"] = True

    try:
        with zipfile.ZipFile(output_path, 'r') as zf:
            # 1. Parse content.xml for body elements
            content = zf.read('content.xml').decode('utf-8', errors='replace')
            
            # Count Heading 1 (outline-level="1")
            # Note: OpenOffice uses <text:h text:outline-level="1"> for Heading 1
            result["heading1_count"] = len(re.findall(r'<text:h[^>]*text:outline-level="1"', content))
            
            # Count Heading 2 (outline-level="2")
            result["heading2_count"] = len(re.findall(r'<text:h[^>]*text:outline-level="2"', content))
            
            # Count Tables
            result["table_count"] = len(re.findall(r'<table:table\b', content))
            
            # Check for Table of Contents
            # ODT uses <text:table-of-content>
            result["has_toc"] = '<text:table-of-content' in content
            
            # Count Paragraphs (simple heuristic)
            result["paragraph_count"] = len(re.findall(r'<text:p\b', content))
            
            # Extract plain text for keyword searching
            plain_text = re.sub(r'<[^>]+>', ' ', content)
            result["text_content_preview"] = plain_text[:500]
            
            # Check keywords
            keywords = [
                "Martinez", "JC-2024", "housing", "parenting", "substance", 
                "attendance", "Centerstone", "Volunteers of America"
            ]
            found = []
            for kw in keywords:
                if kw.lower() in plain_text.lower():
                    found.append(kw)
            result["keywords_found"] = found
            
            # 2. Parse styles.xml (or content.xml) for Page Numbers
            # Page numbers usually in styles.xml under master page footer, but can be in content
            has_pg_num = 'text:page-number' in content
            if not has_pg_num and 'styles.xml' in zf.namelist():
                styles = zf.read('styles.xml').decode('utf-8', errors='replace')
                if 'text:page-number' in styles:
                    has_pg_num = True
            result["has_page_numbers"] = has_pg_num

    except Exception as e:
        result["error"] = str(e)

# Output JSON to temp file
with open('/tmp/analysis_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF "$TASK_START"

# 4. Create final result JSON safely
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat /tmp/analysis_result.json > "$TEMP_JSON"

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="