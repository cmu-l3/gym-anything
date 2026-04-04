#!/bin/bash
echo "=== Exporting Real Estate CMA Report Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Check File Metadata
OUTPUT_FILE="/home/ga/Documents/CMA_Report_4815_Ridgeview.odt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

FILE_EXISTS="false"
FILE_SIZE=0
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Parse ODT Content (using Python inside container)
# We do this here to access container libraries and avoid copying large files to host unnecessarily
# The script outputs a JSON analysis of the document structure
echo "Analyzing document structure..."

python3 << 'PYEOF'
import zipfile
import re
import json
import os
import sys

output_path = "/home/ga/Documents/CMA_Report_4815_Ridgeview.odt"
analysis = {
    "has_toc": False,
    "h1_count": 0,
    "h2_count": 0,
    "table_count": 0,
    "has_footer_pagenum": False,
    "text_content": "",
    "paragraph_count": 0,
    "valid_odt": False
}

if os.path.exists(output_path) and os.path.getsize(output_path) > 0:
    try:
        with zipfile.ZipFile(output_path, 'r') as zf:
            # Analyze content.xml
            if 'content.xml' in zf.namelist():
                content = zf.read('content.xml').decode('utf-8', errors='ignore')
                
                # Check for styles/headings
                analysis['h1_count'] = len(re.findall(r'<text:h[^>]*text:outline-level="1"', content))
                analysis['h2_count'] = len(re.findall(r'<text:h[^>]*text:outline-level="2"', content))
                
                # Check for TOC
                analysis['has_toc'] = 'text:table-of-content' in content
                
                # Check for Tables
                analysis['table_count'] = len(re.findall(r'<table:table ', content))
                
                # Check for page numbers (in content or styles)
                analysis['has_footer_pagenum'] = 'text:page-number' in content
                
                # Extract text for content verification
                plain_text = re.sub(r'<[^>]+>', ' ', content)
                analysis['text_content'] = re.sub(r'\s+', ' ', plain_text).strip()
                
                # meaningful paragraphs
                analysis['paragraph_count'] = len(re.findall(r'<text:p[^>]*>', content))

            # Check styles.xml for footer page numbers if not in content
            if not analysis['has_footer_pagenum'] and 'styles.xml' in zf.namelist():
                styles = zf.read('styles.xml').decode('utf-8', errors='ignore')
                if 'text:page-number' in styles:
                    analysis['has_footer_pagenum'] = True
            
            analysis['valid_odt'] = True
            
    except Exception as e:
        analysis['error'] = str(e)

# Save analysis to temp file
with open('/tmp/odt_analysis.json', 'w') as f:
    json.dump(analysis, f)
PYEOF

# 4. Create Final Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "odt_analysis": $(cat /tmp/odt_analysis.json 2>/dev/null || echo "{}"),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with lenient permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON" /tmp/odt_analysis.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export Complete ==="