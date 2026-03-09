#!/bin/bash
# Export result for generate_reading_list_report

echo "=== Exporting task results ==="
source /workspace/scripts/task_utils.sh

# 1. Basic info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
OUTPUT_PATH="/home/ga/Documents/reading_list.html"

# 2. Capture final screenshot
take_screenshot /tmp/task_final.png

# 3. Analyze Output File
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"
IS_HTML="false"
HAS_TITLES="false"
TITLE_COUNT=0
REPORT_MARKER="false"

if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_PATH")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH")
    
    # Check timestamp
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Check content using python for robustness
    python3 << PYEOF > /tmp/file_analysis.json
import json
import os

filepath = "$OUTPUT_PATH"
result = {
    "is_html": False,
    "titles_found": [],
    "has_report_marker": False
}

try:
    with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
        content = f.read()
        
    # Check HTML signature
    if "<html" in content.lower() or "<!doctype html" in content.lower():
        result["is_html"] = True
        
    # Check for Zotero Report specific markers
    if "zotero report" in content.lower() or "report.css" in content.lower():
        result["has_report_marker"] = True
        
    # Check for expected titles (subset of ML papers)
    expected = [
        "Attention Is All You Need",
        "Deep Learning", 
        "Generative Adversarial Nets",
        "BERT",
        "ImageNet"
    ]
    
    for title in expected:
        if title.lower() in content.lower():
            result["titles_found"].append(title)
            
except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

    # Parse python output
    if [ -f /tmp/file_analysis.json ]; then
        IS_HTML=$(jq -r '.is_html' /tmp/file_analysis.json)
        REPORT_MARKER=$(jq -r '.has_report_marker' /tmp/file_analysis.json)
        TITLE_COUNT=$(jq '.titles_found | length' /tmp/file_analysis.json)
    fi
fi

# 4. Check if Zotero is still running
APP_RUNNING=$(pgrep -f "zotero" > /dev/null && echo "true" || echo "false")

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $FILE_SIZE,
    "is_html": $IS_HTML,
    "has_report_marker": $REPORT_MARKER,
    "title_count": $TITLE_COUNT,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 6. Save to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="