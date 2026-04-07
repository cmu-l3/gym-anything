#!/bin/bash
set -euo pipefail

echo "=== Exporting Task Results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot before doing anything destructive
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check if application was running and gracefully close it
APP_RUNNING="false"
if pgrep -f "onlyoffice-desktopeditors" > /dev/null; then
    APP_RUNNING="true"
    # Attempt graceful save and quit if it's the active window
    DISPLAY=:1 wmctrl -a "ONLYOFFICE" 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key --delay 200 ctrl+s 2>/dev/null || true
    sleep 2
    DISPLAY=:1 xdotool key --delay 200 ctrl+q 2>/dev/null || true
    sleep 2
    pkill -f "onlyoffice-desktopeditors" 2>/dev/null || true
fi

# Evaluate Output File
OUTPUT_PATH="/home/ga/Documents/Presentations/sev1_postmortem.pptx"
FILE_CREATED_DURING_TASK="false"
OUTPUT_EXISTS="false"
OUTPUT_SIZE="0"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Run python-pptx INSIDE the container to parse the document reliably
# This avoids dependency issues on the host evaluator
cat > /tmp/parse_pptx.py << 'PYEOF'
import json, sys
try:
    from pptx import Presentation
    prs = Presentation('/home/ga/Documents/Presentations/sev1_postmortem.pptx')
    slides = []
    for slide in prs.slides:
        text = ""
        has_img = False
        for shape in slide.shapes:
            if hasattr(shape, "text"):
                text += shape.text + " "
            # Check if shape is a picture (Type 13) or named as a picture
            shape_type = getattr(shape, "shape_type", None)
            shape_name = getattr(shape, "name", "").lower()
            if shape_type == 13 or "pic" in shape_name or "image" in shape_name:
                has_img = True
        slides.append({"text": text.strip(), "has_image": has_img})
    print(json.dumps({"success": True, "slides": slides}))
except Exception as e:
    print(json.dumps({"success": False, "error": str(e)}))
PYEOF

PPTX_JSON='{"success": false, "error": "file not found or not parsable"}'
if [ "$OUTPUT_EXISTS" = "true" ]; then
    PPTX_JSON=$(su - ga -c "python3 /tmp/parse_pptx.py" 2>/dev/null || echo '{"success": false, "error": "script execution failed"}')
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "pptx_data": $PPTX_JSON
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="