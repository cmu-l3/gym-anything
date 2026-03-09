#!/bin/bash
# Export script for seasonal_menu_create task
set -e

echo "=== Exporting Seasonal Menu Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Paths
OUTPUT_FILE="/home/ga/Documents/thornfield_spring_menu_2025.odt"
RESULT_JSON="/tmp/task_result.json"

# 3. Analyze output file using Python
# We use Python to parse the ODT (XML in ZIP) structure to verify headers, tables, etc.
python3 << 'PYEOF'
import json
import os
import zipfile
import re
import datetime

output_file = "/home/ga/Documents/thornfield_spring_menu_2025.odt"
result = {
    "file_exists": False,
    "file_size": 0,
    "file_created_during_task": False,
    "heading1_count": 0,
    "heading2_count": 0,
    "table_count": 0,
    "has_toc": False,
    "has_page_numbers": False,
    "text_content": "",
    "timestamp": datetime.datetime.now().isoformat()
}

# Check existence
if os.path.exists(output_file):
    result["file_exists"] = True
    result["file_size"] = os.path.getsize(output_file)
    
    # Check timestamp against task start
    try:
        with open("/tmp/task_start_time.txt", "r") as f:
            start_time = int(f.read().strip())
        mtime = int(os.path.getmtime(output_file))
        if mtime > start_time:
            result["file_created_during_task"] = True
    except:
        # Fallback if timestamp file missing, assume true if file exists now
        result["file_created_during_task"] = True

    try:
        with zipfile.ZipFile(output_file, 'r') as z:
            # Parse content.xml
            content = z.read('content.xml').decode('utf-8', errors='replace')
            
            # Count Heading 1 (outline-level="1")
            # Note: OpenOffice uses <text:h text:outline-level="1">
            result["heading1_count"] = len(re.findall(r'<text:h[^>]*text:outline-level="1"', content))
            
            # Count Heading 2
            result["heading2_count"] = len(re.findall(r'<text:h[^>]*text:outline-level="2"', content))
            
            # Count Tables (<table:table>)
            result["table_count"] = len(re.findall(r'<table:table\b', content))
            
            # Check TOC (<text:table-of-content>)
            result["has_toc"] = '<text:table-of-content' in content
            
            # Check Page Numbers (text:page-number in content or styles)
            styles = ""
            if 'styles.xml' in z.namelist():
                styles = z.read('styles.xml').decode('utf-8', errors='replace')
            
            result["has_page_numbers"] = ('<text:page-number' in content) or ('<text:page-number' in styles)
            
            # Extract plain text for content verification
            # Simple regex strip tags
            text_body = re.sub(r'<[^>]+>', ' ', content)
            # Collapse whitespace
            result["text_content"] = re.sub(r'\s+', ' ', text_body).strip()
            
    except Exception as e:
        result["error"] = str(e)

# Write result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)

PYEOF

# 4. Handle permissions for the result file
chmod 666 "$RESULT_JSON" 2>/dev/null || true

echo "Result exported to $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export Complete ==="