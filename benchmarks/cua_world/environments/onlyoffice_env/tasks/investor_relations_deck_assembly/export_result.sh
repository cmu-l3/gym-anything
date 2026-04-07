#!/bin/bash
set -euo pipefail

echo "=== Exporting Investor Relations Deck Assembly Result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
echo "Capturing final state screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Check application state
APP_RUNNING=$(pgrep -f "onlyoffice-desktopeditors|DesktopEditors" > /dev/null && echo "true" || echo "false")

OUTPUT_PATH="/home/ga/Documents/Presentations/Airbnb_Q3_Summary.pptx"
FILE_EXISTS="false"
FILE_MTIME="0"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"

if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    FILE_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Run a Python script INSIDE the container to parse the PPTX (since python-pptx is available here)
# and dump the contents to JSON, so the verifier on the host can just read the JSON.
cat > /tmp/parse_presentation.py << 'PYEOF'
import sys, os, json
try:
    from pptx import Presentation
except ImportError:
    print(json.dumps({"error": "python-pptx library not found"}))
    sys.exit(0)

target_file = "/home/ga/Documents/Presentations/Airbnb_Q3_Summary.pptx"
result = {
    "slides": []
}

if os.path.exists(target_file):
    try:
        prs = Presentation(target_file)
        for slide in prs.slides:
            slide_text = []
            for shape in slide.shapes:
                if hasattr(shape, "text") and shape.text:
                    slide_text.append(shape.text)
            result["slides"].append("\n".join(slide_text))
    except Exception as e:
        result["error"] = str(e)

print(json.dumps(result))
PYEOF

echo "Parsing presentation contents..."
SLIDE_DATA=$(sudo -u ga python3 /tmp/parse_presentation.py)

# Generate the final result JSON payload
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "output_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $FILE_SIZE,
    "slide_data": $SLIDE_DATA
}
EOF

# Move payload safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON generated."
cat /tmp/task_result.json

echo "=== Export complete ==="