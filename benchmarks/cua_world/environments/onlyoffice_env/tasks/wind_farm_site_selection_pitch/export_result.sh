#!/bin/bash
set -euo pipefail

echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot BEFORE closing
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Force save and close ONLYOFFICE gracefully if possible
if pgrep -f "onlyoffice" > /dev/null; then
    DISPLAY=:1 wmctrl -a "ONLYOFFICE" 2>/dev/null || true
    sleep 1
    DISPLAY=:1 xdotool key ctrl+s 2>/dev/null || true
    sleep 2
    pkill -f "onlyoffice" || true
    sleep 2
fi

PPTX_PATH="/home/ga/Documents/Presentations/site_alpha_pitch.pptx"
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"

# Check if file exists and was created during the task window
if [ -f "$PPTX_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$PPTX_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$PPTX_PATH" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Parse PPTX to extract text using python-pptx inside the container
cat > /tmp/parse_pptx.py << 'PYEOF'
import sys
import json
import os

pptx_path = '/home/ga/Documents/Presentations/site_alpha_pitch.pptx'
truth_path = '/var/lib/app/ground_truth/wind_metrics.json'

result = {
    "pptx_parsed": False,
    "slide_count": 0,
    "text_content": "",
    "ground_truth": {}
}

# Load Ground Truth
if os.path.exists(truth_path):
    with open(truth_path, 'r') as f:
        result["ground_truth"] = json.load(f)

# Parse Presentation
if os.path.exists(pptx_path):
    try:
        from pptx import Presentation
        prs = Presentation(pptx_path)
        text_elements = []
        for slide in prs.slides:
            for shape in slide.shapes:
                if hasattr(shape, "text"):
                    text_elements.append(shape.text)
        
        result["pptx_parsed"] = True
        result["slide_count"] = len(prs.slides)
        result["text_content"] = " ||| ".join(text_elements)
    except Exception as e:
        result["parse_error"] = str(e)

with open('/tmp/pptx_data.json', 'w') as f:
    json.dump(result, f)
PYEOF

python3 /tmp/parse_pptx.py

# Read the parsed JSON back
PPTX_JSON=$(cat /tmp/pptx_data.json)

# Combine into final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size_bytes": $FILE_SIZE,
    "parsed_data": $PPTX_JSON
}
EOF

# Ensure safe permissions
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="