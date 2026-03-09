#!/bin/bash
set -e
echo "=== Exporting duplicate_regional_slides result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
ODP_PATH="/home/ga/Documents/Presentations/quarterly_review.odp"

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check file stats
FILE_EXISTS="false"
FILE_MODIFIED="false"
FILE_SIZE="0"

if [ -f "$ODP_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$ODP_PATH")
    FILE_MTIME=$(stat -c %Y "$ODP_PATH")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# 3. Analyze ODP content inside the container using Python
# We do this here to avoid complex dependency requirements on the verifier side
# This script extracts slide count and text content into a JSON structure
python3 << 'PYEOF' > /tmp/odp_analysis.json
import json
import sys
import os

try:
    from odf import opendocument, draw, text
    
    filepath = "/home/ga/Documents/Presentations/quarterly_review.odp"
    if not os.path.exists(filepath):
        print(json.dumps({"error": "File not found"}))
        sys.exit(0)
        
    doc = opendocument.load(filepath)
    slides = []
    
    # Iterate through slides (draw:page)
    for page in doc.getElementsByType(draw.Page):
        slide_content = {
            "title": "",
            "text": []
        }
        
        # Extract text paragraphs
        # In Impress ODP, titles are often in specific text boxes, but getting all text is safer
        for t in page.getElementsByType(text.P):
            content = str(t)
            if content.strip():
                slide_content["text"].append(content.strip())
        
        # Heuristic: First non-empty text usually title, or specific title object
        # We'll just dump all text for the verifier to search through
        slides.append(slide_content)
        
    print(json.dumps({
        "slide_count": len(slides),
        "slides": slides,
        "success": True
    }))

except Exception as e:
    print(json.dumps({
        "success": False,
        "error": str(e),
        "slide_count": 0,
        "slides": []
    }))
PYEOF

# 4. Construct final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 << PYEOF > "$TEMP_JSON"
import json

try:
    with open('/tmp/odp_analysis.json', 'r') as f:
        analysis = json.load(f)
except:
    analysis = {"success": False, "error": "Analysis failed"}

result = {
    "task_start": $TASK_START,
    "file_exists": "$FILE_EXISTS" == "true",
    "file_modified": "$FILE_MODIFIED" == "true",
    "file_size": $FILE_SIZE,
    "analysis": analysis
}

print(json.dumps(result))
PYEOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="