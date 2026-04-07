#!/bin/bash
echo "=== Exporting create_hubble_palette_composite result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Run Python script inside the container to analyze the image
# This ensures we use the container's installed PIL/numpy to safely extract stats
cat > /tmp/analyze_image.py << 'PYEOF'
import json
import os
import time

result = {
    "output_exists": False,
    "created_during_task": False,
    "is_rgb": False,
    "mean_intensity": 0.0,
    "std_rg": 0.0,
    "std_gb": 0.0,
    "std_rb": 0.0,
    "error": None
}

output_path = "/home/ga/AstroImages/processed/eagle_hubble_palette.png"

# Read task start time
task_start = 0
try:
    with open("/tmp/task_start_time.txt", "r") as f:
        task_start = int(f.read().strip())
except Exception:
    pass

if os.path.exists(output_path):
    result["output_exists"] = True
    
    # Check modification time
    mtime = os.path.getmtime(output_path)
    if mtime >= task_start:
        result["created_during_task"] = True
        
    try:
        from PIL import Image
        import numpy as np
        
        img = Image.open(output_path)
        
        # Check if it's an RGB image
        if img.mode in ['RGB', 'RGBA']:
            result["is_rgb"] = True
            
        # Convert to RGB array for analysis
        img_arr = np.array(img.convert('RGB'))
        
        # Calculate mean intensity (checks if image was stretched/not black)
        result["mean_intensity"] = float(np.mean(img_arr))
        
        # Calculate standard deviation between channels to ensure true false-color
        # (If all channels are identical, the image is grayscale)
        r = img_arr[:,:,0].astype(float)
        g = img_arr[:,:,1].astype(float)
        b = img_arr[:,:,2].astype(float)
        
        result["std_rg"] = float(np.std(r - g))
        result["std_gb"] = float(np.std(g - b))
        result["std_rb"] = float(np.std(r - b))
        
    except Exception as e:
        result["error"] = str(e)

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

python3 /tmp/analyze_image.py

# Check if application was running
APP_RUNNING="false"
if is_aij_running; then
    APP_RUNNING="true"
fi

# Inject app_running into json using a quick jq alternative with python
python3 -c "
import json
with open('/tmp/task_result.json', 'r') as f:
    data = json.load(f)
data['app_running'] = '$APP_RUNNING' == 'true'
with open('/tmp/task_result.json', 'w') as f:
    json.dump(data, f)
"

# Set permissions so verifier can easily copy it
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json:"
cat /tmp/task_result.json
echo "=== Export complete ==="