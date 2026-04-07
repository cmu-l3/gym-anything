#!/bin/bash
echo "=== Exporting Prepare Publication Image Results ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_end_screenshot.png

# We will use Python to check if the file exists, if it was created during the task,
# and programmatically analyze its color channels to ensure a false-color LUT was applied.
python3 << 'PYEOF'
import json
import os
import time

try:
    with open("/tmp/task_start_time.txt", "r") as f:
        task_start = float(f.read().strip())
except:
    task_start = 0.0

output_path = "/home/ga/AstroImages/publication/output/eagle_publication.png"

result = {
    "output_exists": False,
    "created_during_task": False,
    "width": 0,
    "height": 0,
    "is_false_color": False,
    "color_variance": 0.0,
    "file_size_bytes": 0,
    "error": None
}

if os.path.exists(output_path):
    result["output_exists"] = True
    mtime = os.path.getmtime(output_path)
    result["file_size_bytes"] = os.path.getsize(output_path)
    result["created_during_task"] = mtime >= task_start
    
    try:
        from PIL import Image
        import numpy as np
        
        img = Image.open(output_path).convert('RGB')
        result["width"] = img.width
        result["height"] = img.height
        
        # Analyze RGB channels to verify it is NOT grayscale
        # If the image is grayscale, R == G == B, and variance between them is ~0
        # If a false-color LUT was applied, channels will differ significantly
        arr = np.array(img, dtype=np.float32)
        r, g, b = arr[:,:,0], arr[:,:,1], arr[:,:,2]
        
        diff_rg_std = float(np.std(r - g))
        diff_gb_std = float(np.std(g - b))
        total_color_variance = diff_rg_std + diff_gb_std
        
        result["color_variance"] = total_color_variance
        
        # Threshold for determining if false color is applied (> 5.0 variance)
        result["is_false_color"] = total_color_variance > 5.0

    except Exception as e:
        result["error"] = str(e)

# Save programmatic results
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Export data generated:")
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="