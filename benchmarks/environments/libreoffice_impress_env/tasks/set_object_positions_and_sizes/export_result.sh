#!/bin/bash
set -e
echo "=== Exporting set_object_positions_and_sizes result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Capture final screenshot before closing anything
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Close LibreOffice gracefully to ensure save (if agent forgot, though task says they should save)
# We won't force save, just close. If they didn't save, verification fails (anti-gaming).
pkill -f soffice 2>/dev/null || true
sleep 2

# Path handling
PPTX_PATH="/home/ga/Documents/Presentations/chip_layout.pptx"
ODP_PATH="/home/ga/Documents/Presentations/chip_layout.odp"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Check which file exists (user might have saved as ODP)
TARGET_FILE=""
FILE_FORMAT=""

if [ -f "$PPTX_PATH" ]; then
    TARGET_FILE="$PPTX_PATH"
    FILE_FORMAT="pptx"
elif [ -f "$ODP_PATH" ]; then
    TARGET_FILE="$ODP_PATH"
    FILE_FORMAT="odp"
    # Convert ODP to PPTX for easier verification with python-pptx
    echo "Converting ODP to PPTX for verification..."
    libreoffice --headless --convert-to pptx --outdir "$(dirname "$ODP_PATH")" "$ODP_PATH" >/dev/null 2>&1
    # Update target to the converted file
    TARGET_FILE="$PPTX_PATH"
fi

# File modification check
FILE_MODIFIED="false"
if [ -n "$TARGET_FILE" ] && [ -f "$TARGET_FILE" ]; then
    FILE_MTIME=$(stat -c %Y "$TARGET_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Analyze the presentation using python-pptx inside the container
# We extract the metrics here to avoid dependency issues on the host verifier
echo "Analyzing presentation structure..."
python3 << PYEOF > /tmp/analysis_output.json
import json
import sys
import os

try:
    from pptx import Presentation
    from pptx.util import Cm, Emu

    result = {
        "error": None,
        "shapes_found": {},
        "slide_count": 0
    }
    
    target_file = "$TARGET_FILE"
    
    if not os.path.exists(target_file):
        result["error"] = "File not found"
        print(json.dumps(result))
        sys.exit(0)

    prs = Presentation(target_file)
    result["slide_count"] = len(prs.slides)
    
    if len(prs.slides) >= 2:
        slide = prs.slides[1] # Slide 2
        
        # Helper to convert EMU to CM
        def emu_to_cm(emu):
            return round(emu / 914400 * 2.54, 2)
            
        for shape in slide.shapes:
            # Match shapes by name or text content
            name = shape.name
            text = ""
            if hasattr(shape, "text_frame") and shape.text_frame:
                text = shape.text_frame.text
            
            # Identify target shapes
            key = None
            if "CPU" in name or "CPU" in text:
                key = "CPU Core"
            elif "Memory" in name or "Memory" in text:
                key = "Memory Controller"
            elif "I/O" in name or "I/O" in text:
                key = "I/O Interface"
            
            if key:
                result["shapes_found"][key] = {
                    "x": emu_to_cm(shape.left),
                    "y": emu_to_cm(shape.top),
                    "w": emu_to_cm(shape.width),
                    "h": emu_to_cm(shape.height)
                }
                
    print(json.dumps(result))

except Exception as e:
    print(json.dumps({"error": str(e), "shapes_found": {}}))
PYEOF

# Create final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
ANALYSIS=$(cat /tmp/analysis_output.json)
INITIAL_STATE=$(cat /tmp/initial_shape_state.json 2>/dev/null || echo "{}")

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $([ -n "$TARGET_FILE" ] && echo "true" || echo "false"),
    "file_format": "$FILE_FORMAT",
    "file_modified": $FILE_MODIFIED,
    "analysis": $ANALYSIS,
    "initial_state": $INITIAL_STATE
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="