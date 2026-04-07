#!/bin/bash
echo "=== Exporting chromakey_blue_bg_render result ==="

OUTPUT_DIR="/home/ga/OpenToonz/output/chromakey_render"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Analyze Output Files
# We use an embedded Python script to analyze the rendered images for color and content.
# This script calculates the average background color of the output frames.

cat << 'EOF' > /tmp/analyze_frames.py
import os
import sys
import json
import glob
from PIL import Image

output_dir = sys.argv[1]
task_start = float(sys.argv[2])

result = {
    "frame_count": 0,
    "valid_frames": 0,
    "avg_bg_color": [0, 0, 0],
    "is_transparent": False,
    "files_created_during_task": True,
    "total_size_kb": 0,
    "error": None
}

try:
    files = sorted(glob.glob(os.path.join(output_dir, "*.png")))
    result["frame_count"] = len(files)
    
    if not files:
        result["error"] = "No PNG files found"
        print(json.dumps(result))
        sys.exit(0)

    # Check timestamps
    for f in files:
        if os.path.getmtime(f) <= task_start:
            result["files_created_during_task"] = False
            break
            
    # Calculate total size
    total_size = sum(os.path.getsize(f) for f in files)
    result["total_size_kb"] = total_size / 1024

    # Analyze color of the first valid frame (assuming sequence consistency)
    # We sample corners to find the background color
    sample_frame_path = files[0]
    try:
        img = Image.open(sample_frame_path).convert("RGBA")
        width, height = img.size
        
        # Sample 4 corners (assuming character is centered and not touching corners)
        corners = [
            (0, 0),
            (width - 1, 0),
            (0, height - 1),
            (width - 1, height - 1)
        ]
        
        r_total, g_total, b_total, a_total = 0, 0, 0, 0
        valid_samples = 0
        
        for x, y in corners:
            r, g, b, a = img.getpixel((x, y))
            r_total += r
            g_total += g
            b_total += b
            a_total += a
            valid_samples += 1
            
        if valid_samples > 0:
            avg_a = a_total / valid_samples
            # If alpha is low, it's transparent
            if avg_a < 250: 
                result["is_transparent"] = True
            
            # If transparent, the RGB values might be pre-multiplied or 0, 
            # but we record them anyway.
            result["avg_bg_color"] = [
                int(r_total / valid_samples),
                int(g_total / valid_samples),
                int(b_total / valid_samples)
            ]
            
        result["valid_frames"] = len(files) # Simplified valid check

    except Exception as e:
        result["error"] = f"Image analysis failed: {str(e)}"

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
EOF

# Run the analysis
# Install PIL if missing (should be in env, but safety first)
if ! python3 -c "import PIL" 2>/dev/null; then
    pip3 install pillow > /dev/null 2>&1
fi

ANALYSIS_JSON=$(python3 /tmp/analyze_frames.py "$OUTPUT_DIR" "$TASK_START")

# 3. Construct Final JSON
# We merge the analysis with basic environment info
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "analysis": $ANALYSIS_JSON,
    "task_start": $TASK_START,
    "timestamp": "$(date -Iseconds)",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 4. Save to standardized location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON" /tmp/analyze_frames.py

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="