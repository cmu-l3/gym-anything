#!/bin/bash
set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Task Results ==="

TARGET_FILE="/home/ga/Documents/Presentations/product_showcase.odp"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check file modification
FILE_MODIFIED="false"
if [ -f "$TARGET_FILE" ]; then
    FILE_MTIME=$(stat -c %Y "$TARGET_FILE")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# 3. Extract geometric data from Slide 2 using python script inside env
# This avoids needing ODF libraries on the verifier host
echo "Analyzing slide geometry..."
python3 << PYEOF > /tmp/geometry_analysis.json
import json
import sys
import re

try:
    from odf.opendocument import load
    from odf.draw import Frame
    
    doc = load("$TARGET_FILE")
    
    # Get Slide 2 (index 1)
    slides = doc.presentation.getElementsByType(eval("from odf.draw import Page; Page"))
    if len(slides) < 2:
        print(json.dumps({"error": "Slide 2 not found", "slide_count": len(slides)}))
        sys.exit(0)
        
    slide2 = slides[1]
    
    # Helper to parse length strings like "2.54cm", "1in" to cm
    def parse_length(length_str):
        if not length_str: return 0.0
        val = float(re.findall(r"[\d\.]+", length_str)[0])
        if "cm" in length_str: return val
        if "mm" in length_str: return val / 10.0
        if "in" in length_str: return val * 2.54
        if "pt" in length_str: return val * 0.0352778
        return val # Assume cm if no unit or parse fail

    # Find image frames
    # In ODF, images are typically inside draw:frame elements
    frames = []
    for frame in slide2.getElementsByType(Frame):
        # Check if it contains an image
        if frame.getElementsByType(eval("from odf.draw import Image; Image")):
            x = parse_length(frame.getAttribute("x"))
            y = parse_length(frame.getAttribute("y"))
            w = parse_length(frame.getAttribute("width"))
            h = parse_length(frame.getAttribute("height"))
            frames.append({"x": x, "y": y, "width": w, "height": h})

    # Sort frames by X position to determine order
    frames.sort(key=lambda f: f["x"])
    
    result = {
        "image_count": len(frames),
        "frames": frames,
        "success": True
    }
    print(json.dumps(result))

except Exception as e:
    print(json.dumps({"error": str(e), "success": False}))
PYEOF

# 4. Create final result JSON
cat > /tmp/task_result.json << EOF
{
    "file_modified": $FILE_MODIFIED,
    "geometry": $(cat /tmp/geometry_analysis.json),
    "timestamp": "$(date +%s)"
}
EOF

# Ensure permissions for copy_from_env
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json