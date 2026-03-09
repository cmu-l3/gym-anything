#!/bin/bash
echo "=== Exporting hide_confidential_slides results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
PRES_DIR="/home/ga/Documents/Presentations"

# Take final screenshot
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Close LibreOffice gracefully to ensure save (if user forgot)
# Note: In real task, we expect user to save. We check file on disk.
# We won't force save here to strictly test user action, but we will check if app is running.
APP_RUNNING=$(pgrep -f "soffice.bin" > /dev/null && echo "true" || echo "false")

# Identify the target file (could be .pptx or .odp)
# We look for the most recently modified file matching the pattern
TARGET_FILE=""
LATEST_TIME=0

for f in "$PRES_DIR"/quarterly_review.*; do
    if [ -f "$f" ]; then
        MTIME=$(stat -c %Y "$f")
        if [ "$MTIME" -gt "$LATEST_TIME" ]; then
            LATEST_TIME=$MTIME
            TARGET_FILE="$f"
        fi
    fi
done

echo "Target file found: $TARGET_FILE"

# Create Python script to analyze slide visibility
# This runs INSIDE the container to access local libraries and files
cat > /tmp/analyze_slides.py << 'PYEOF'
import sys
import json
import os
import zipfile
from lxml import etree

def analyze_odp(filepath):
    results = {"total_slides": 0, "hidden_indices": []}
    try:
        with zipfile.ZipFile(filepath, 'r') as z:
            content = z.read('content.xml')
        
        root = etree.fromstring(content)
        ns_draw = 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0'
        ns_pres = 'urn:oasis:names:tc:opendocument:xmlns:presentation:1.0'
        
        pages = root.findall(f'.//{{{ns_draw}}}page')
        results["total_slides"] = len(pages)
        
        for i, page in enumerate(pages):
            vis = page.get(f'{{{ns_pres}}}visibility')
            # 1-based index
            if vis == 'hidden':
                results["hidden_indices"].append(i + 1)
                
        return results
    except Exception as e:
        return {"error": str(e)}

def analyze_pptx(filepath):
    results = {"total_slides": 0, "hidden_indices": []}
    try:
        from pptx import Presentation
        prs = Presentation(filepath)
        results["total_slides"] = len(prs.slides)
        
        for i, slide in enumerate(prs.slides):
            # 1-based index
            # In python-pptx, access element attribute for show/hide
            # show="0" means hidden
            show_attr = slide._element.get('show')
            if show_attr == '0' or show_attr == 0:
                results["hidden_indices"].append(i + 1)
        
        return results
    except Exception as e:
        return {"error": str(e)}

if __name__ == "__main__":
    filepath = sys.argv[1]
    ext = os.path.splitext(filepath)[1].lower()
    
    data = {}
    if ext == ".odp":
        data = analyze_odp(filepath)
        data["format"] = "odp"
    elif ext == ".pptx":
        data = analyze_pptx(filepath)
        data["format"] = "pptx"
    else:
        data = {"error": "Unknown format"}
    
    print(json.dumps(data))
PYEOF

# Run analysis
if [ -n "$TARGET_FILE" ] && [ -f "$TARGET_FILE" ]; then
    ANALYSIS_JSON=$(python3 /tmp/analyze_slides.py "$TARGET_FILE")
    
    # File modification info
    FILE_MTIME=$(stat -c %Y "$TARGET_FILE")
    FILE_SIZE=$(stat -c %s "$TARGET_FILE")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        MODIFIED_DURING_TASK="true"
    else
        MODIFIED_DURING_TASK="false"
    fi
    
    # Initial hash check
    CURRENT_HASH=$(md5sum "$TARGET_FILE" | awk '{print $1}')
    INITIAL_HASH=$(cat /tmp/initial_file_hash.txt 2>/dev/null || echo "")
    
    if [ "$CURRENT_HASH" != "$INITIAL_HASH" ]; then
        CONTENT_CHANGED="true"
    else
        CONTENT_CHANGED="false"
    fi
    
    FILE_EXISTS="true"
else
    ANALYSIS_JSON='{"total_slides": 0, "hidden_indices": [], "error": "File not found"}'
    FILE_EXISTS="false"
    MODIFIED_DURING_TASK="false"
    CONTENT_CHANGED="false"
    FILE_SIZE=0
fi

# Compile final result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_path": "$TARGET_FILE",
    "file_size_bytes": $FILE_SIZE,
    "modified_during_task": $MODIFIED_DURING_TASK,
    "content_changed": $CONTENT_CHANGED,
    "app_running": $APP_RUNNING,
    "slide_analysis": $ANALYSIS_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="