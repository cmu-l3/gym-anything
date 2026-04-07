#!/bin/bash
echo "=== Exporting square_scene_colorcard_render results ==="

OUTPUT_DIR="/home/ga/OpenToonz/output/square_scene"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULT_JSON="/tmp/task_result.json"

# 1. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Analyze Output Files using Python (running inside the container)
# We use python3-pil/numpy to analyze resolution and color
cat > /tmp/analyze_output.py << 'EOF'
import os
import glob
import json
import sys
import time

try:
    from PIL import Image
    import numpy as np
except ImportError:
    # Fallback if libraries missing (unlikely in this env)
    print(json.dumps({"error": "Missing PIL/numpy"}))
    sys.exit(0)

output_dir = "/home/ga/OpenToonz/output/square_scene"
task_start = int(sys.argv[1]) if len(sys.argv) > 1 else 0

result = {
    "files_found": False,
    "file_count": 0,
    "files_created_during_task": 0,
    "total_size_bytes": 0,
    "width": 0,
    "height": 0,
    "avg_color": [0, 0, 0],
    "is_solid_color": False,
    "error": None
}

try:
    # Get all PNG files
    files = sorted(glob.glob(os.path.join(output_dir, "*.png")))
    result["file_count"] = len(files)
    
    if files:
        result["files_found"] = True
        
        # Check timestamps and size
        new_files_count = 0
        total_size = 0
        for f in files:
            stats = os.stat(f)
            total_size += stats.st_size
            if stats.st_mtime > task_start:
                new_files_count += 1
        
        result["files_created_during_task"] = new_files_count
        result["total_size_bytes"] = total_size

        # Analyze the first file for resolution and color
        # We assume all frames are similar
        first_img_path = files[0]
        with Image.open(first_img_path) as img:
            img = img.convert('RGB')
            result["width"], result["height"] = img.size
            
            # Analyze color (sample center region)
            # Sample a 50x50 patch from center
            cx, cy = result["width"] // 2, result["height"] // 2
            box = (max(0, cx-25), max(0, cy-25), min(result["width"], cx+25), min(result["height"], cy+25))
            
            # Convert to numpy for fast calc
            crop = np.array(img.crop(box))
            
            # Calculate average color
            avg = np.mean(crop, axis=(0, 1))
            result["avg_color"] = [float(avg[0]), float(avg[1]), float(avg[2])]
            
            # Check deviation to confirm solid color (low variance)
            std = np.std(crop, axis=(0, 1))
            # If standard deviation is low, it's likely a solid color card
            result["is_solid_color"] = float(np.mean(std)) < 10.0

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
EOF

# Run the analysis script
echo "Running analysis..."
python3 /tmp/analyze_output.py "$TASK_START" > "$RESULT_JSON"

# 3. Check if OpenToonz is still running
APP_RUNNING="false"
if pgrep -f "opentoonz" > /dev/null; then
    APP_RUNNING="true"
fi

# Append app status to the JSON (using a temporary merge file)
cat > /tmp/merge_json.py << EOF
import json
with open('$RESULT_JSON', 'r') as f:
    data = json.load(f)
data['app_running'] = $APP_RUNNING
data['screenshot_path'] = '/tmp/task_final.png'
with open('$RESULT_JSON', 'w') as f:
    json.dump(data, f)
EOF
python3 /tmp/merge_json.py

# 4. Set permissions so the host can copy it
chmod 666 "$RESULT_JSON" /tmp/task_final.png 2>/dev/null || true

echo "Result saved to $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export complete ==="