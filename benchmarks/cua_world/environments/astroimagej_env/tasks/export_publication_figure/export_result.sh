#!/bin/bash
echo "=== Exporting Publication Figure Results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# The path where the agent is supposed to save the PNG
OUTPUT_PNG="/home/ga/AstroImages/publication/eagle_figure.png"

# We will use Python to deeply analyze the exported PNG file 
# to ensure it meets spatial and color criteria.
cat > /tmp/analyze_png.py << 'EOF'
import json
import os
import sys

# Try importing image libraries
try:
    from PIL import Image
    import numpy as np
    LIBS_AVAILABLE = True
except ImportError:
    LIBS_AVAILABLE = False

output_path = sys.argv[1]
task_start = float(sys.argv[2])

result = {
    "output_exists": False,
    "created_during_task": False,
    "width": 0,
    "height": 0,
    "mean_r": 0.0,
    "mean_g": 0.0,
    "mean_b": 0.0,
    "is_color": False,
    "scale_bar_length_pixels": 0,
    "analysis_error": None,
    "libs_available": LIBS_AVAILABLE
}

if os.path.exists(output_path):
    result["output_exists"] = True
    mtime = os.path.getmtime(output_path)
    if mtime >= task_start:
        result["created_during_task"] = True

    if LIBS_AVAILABLE:
        try:
            img = Image.open(output_path).convert('RGB')
            arr = np.array(img)
            h, w, c = arr.shape
            result["width"] = w
            result["height"] = h
            
            # Calculate mean of color channels
            r_mean = float(np.mean(arr[:,:,0]))
            g_mean = float(np.mean(arr[:,:,1]))
            b_mean = float(np.mean(arr[:,:,2]))
            
            result["mean_r"] = r_mean
            result["mean_g"] = g_mean
            result["mean_b"] = b_mean
            
            # Grayscale images have identical R, G, B. 
            # If variance across channels is > 1, it has a color LUT applied.
            if abs(r_mean - b_mean) > 5.0 or abs(r_mean - g_mean) > 5.0:
                result["is_color"] = True
                
            # Find the longest horizontal white line (scale bar detection)
            # White in RGB is [255, 255, 255] or very close
            white_mask = (arr[:,:,0] > 250) & (arr[:,:,1] > 250) & (arr[:,:,2] > 250)
            
            max_line = 0
            for row in white_mask:
                runs = np.where(row)[0]
                if len(runs) > 0:
                    # Find consecutive sequences of white pixels
                    consecutive = np.split(runs, np.where(np.diff(runs) != 1)[0] + 1)
                    longest = max(len(c) for c in consecutive)
                    if longest > max_line:
                        max_line = longest
                        
            result["scale_bar_length_pixels"] = max_line
            
        except Exception as e:
            result["analysis_error"] = str(e)

# Output JSON
print(json.dumps(result, indent=2))
EOF

# Run analysis script and capture output
python3 /tmp/analyze_png.py "$OUTPUT_PNG" "$TASK_START" > /tmp/task_result.json

# Cleanup and permission handling
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "PNG Analysis Results:"
cat /tmp/task_result.json

echo "=== Export Complete ==="