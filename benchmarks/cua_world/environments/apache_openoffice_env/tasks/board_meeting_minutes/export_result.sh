#!/bin/bash
set -e
echo "=== Exporting board_meeting_minutes result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

OUTPUT_PATH="/home/ga/Documents/RCHD_Board_Minutes_2024-11-14.odt"

# Take final screenshot
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Python script to parse ODT and extract verification metrics
# We use a temp python script to avoid escaping hell
cat > /tmp/analyze_odt.py << 'PYEOF'
import zipfile
import json
import os
import re
import sys

output_path = "/home/ga/Documents/RCHD_Board_Minutes_2024-11-14.odt"
result = {
    "file_exists": False,
    "file_size": 0,
    "is_valid_zip": False,
    "heading1_count": 0,
    "heading2_count": 0,
    "table_count": 0,
    "has_toc": False,
    "has_page_numbers": False,
    "paragraph_count": 0,
    "plain_text": "",
    "error": None
}

if os.path.exists(output_path):
    result["file_exists"] = True
    result["file_size"] = os.path.getsize(output_path)
    
    try:
        if zipfile.is_zipfile(output_path):
            result["is_valid_zip"] = True
            with zipfile.ZipFile(output_path, 'r') as zf:
                # Read content.xml
                content = zf.read('content.xml').decode('utf-8', errors='replace')
                
                # Check for styles.xml (footer often here)
                styles = ""
                if 'styles.xml' in zf.namelist():
                    styles = zf.read('styles.xml').decode('utf-8', errors='replace')
                
                # Count Headings
                # Note: OpenOffice usually saves headings as <text:h text:outline-level="X">
                result["heading1_count"] = len(re.findall(r'<text:h[^>]*text:outline-level="1"', content))
                result["heading2_count"] = len(re.findall(r'<text:h[^>]*text:outline-level="2"', content))
                
                # Count Tables
                result["table_count"] = len(re.findall(r'<table:table\b', content))
                
                # Check TOC
                result["has_toc"] = 'text:table-of-content' in content
                
                # Check Page Numbers
                # Can be in content.xml or styles.xml (usually in styles.xml for footer)
                result["has_page_numbers"] = ('text:page-number' in content) or ('text:page-number' in styles)
                
                # Count Paragraphs (simple count of text:p)
                result["paragraph_count"] = len(re.findall(r'<text:p\b', content))
                
                # Extract plain text for content verification
                # Remove tags
                text = re.sub(r'<[^>]+>', ' ', content)
                # Normalize whitespace
                text = re.sub(r'\s+', ' ', text).strip()
                result["plain_text"] = text.lower()  # normalized for case-insensitive check
                
    except Exception as e:
        result["error"] = str(e)

# Output JSON to stdout
print(json.dumps(result))
PYEOF

# Run analysis and save to temp file
python3 /tmp/analyze_odt.py > /tmp/analysis_result.json

# Combine into final result structure
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "screenshot_path": "/tmp/task_final.png",
    "analysis": $(cat /tmp/analysis_result.json)
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="