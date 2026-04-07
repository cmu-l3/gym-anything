#!/bin/bash
echo "=== Exporting greenscreen_bg_render results ==="

OUTPUT_DIR="/home/ga/OpenToonz/output/greenscreen"
RESULT_FILE="/tmp/task_result.json"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Gather file stats
PNG_COUNT=0
TOTAL_SIZE=0
NEWEST_FILES=0

if [ -d "$OUTPUT_DIR" ]; then
    # Count PNG/TGA files
    PNG_COUNT=$(find "$OUTPUT_DIR" -maxdepth 1 \( -name "*.png" -o -name "*.tga" -o -name "*.PNG" \) 2>/dev/null | wc -l)

    # Total size
    TOTAL_SIZE=$(du -sb "$OUTPUT_DIR" 2>/dev/null | cut -f1 || echo "0")

    # Files created after task start
    if [ "$TASK_START" != "0" ]; then
        NEWEST_FILES=$(find "$OUTPUT_DIR" -maxdepth 1 \( -name "*.png" -o -name "*.tga" \) -newer /tmp/task_start_time.txt 2>/dev/null | wc -l)
    fi
fi

# 2. Pixel Analysis (Embedded Python)
# We run this inside the VM to inspect the actual generated images
PIXEL_ANALYSIS="{}"
if [ "$PNG_COUNT" -gt 0 ]; then
    echo "Running pixel analysis on output frames..."
    python3 << 'PYEOF'
import json
import os
import glob
from PIL import Image

output_dir = "/home/ga/OpenToonz/output/greenscreen"
result = {
    "dimensions": None,
    "consistent_dims": False,
    "green_score": 0.0,
    "frames_checked": 0,
    "samples": []
}

files = sorted(glob.glob(os.path.join(output_dir, "*.png"))) + \
        sorted(glob.glob(os.path.join(output_dir, "*.tga")))

if files:
    dims_list = []
    green_ratios = []
    
    # Check first 20 frames max
    for f in files[:20]:
        try:
            img = Image.open(f).convert("RGB")
            w, h = img.size
            dims_list.append((w, h))
            
            # Sample points: Corners and Edge Midpoints
            # Margin prevents hitting antialiasing artifacts at very edge
            m = 2 
            points = [
                (m, m), (w-m, m), (m, h-m), (w-m, h-m), # Corners
                (w//2, m), (w//2, h-m), (m, h//2), (w-m, h//2) # Midpoints
            ]
            
            green_hits = 0
            for x, y in points:
                # Clamp coords
                x = min(max(0, x), w-1)
                y = min(max(0, y), h-1)
                
                r, g, b = img.getpixel((x, y))
                
                # Check for Green (0, 255, 0) with tolerance
                # R and B should be low (<20), G should be high (>230)
                if r < 30 and b < 30 and g > 220:
                    green_hits += 1
            
            green_ratios.append(green_hits / len(points))
            
        except Exception as e:
            print(f"Error reading {f}: {e}")

    if dims_list:
        result["dimensions"] = dims_list[0]
        result["consistent_dims"] = all(d == dims_list[0] for d in dims_list)
        result["frames_checked"] = len(dims_list)
    
    if green_ratios:
        result["green_score"] = sum(green_ratios) / len(green_ratios)
        # Add sample data for debug/verification
        result["samples"] = green_ratios[:5]

with open("/tmp/pixel_analysis.json", "w") as f:
    json.dump(result, f)
PYEOF

    if [ -f /tmp/pixel_analysis.json ]; then
        PIXEL_ANALYSIS=$(cat /tmp/pixel_analysis.json)
    fi
fi

# 3. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || true

# 4. Write Result JSON
cat > "$RESULT_FILE" << JSONEOF
{
    "png_count": $PNG_COUNT,
    "total_size_bytes": $TOTAL_SIZE,
    "newer_than_start": $NEWEST_FILES,
    "task_start": $TASK_START,
    "pixel_analysis": $PIXEL_ANALYSIS,
    "screenshot_path": "/tmp/task_final_state.png"
}
JSONEOF

# Ensure permissions
chmod 666 "$RESULT_FILE" 2>/dev/null || true

echo "Result saved to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export complete ==="