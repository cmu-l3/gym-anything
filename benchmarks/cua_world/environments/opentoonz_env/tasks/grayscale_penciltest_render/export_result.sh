#!/bin/bash
echo "=== Exporting grayscale_penciltest_render result ==="

# Paths
OUTPUT_DIR="/home/ga/OpenToonz/output/grayscale_test"
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || true

# 2. Run Python analysis script inside the container
# This calculates file counts, freshness, and grayscale metrics using PIL/numpy
# We write the script to a temp file and execute it
cat > /tmp/analyze_results.py << 'EOF'
import os
import glob
import json
import time
import sys

try:
    from PIL import Image, ImageStat
    import numpy as np
except ImportError:
    print("Error: PIL or numpy not installed", file=sys.stderr)
    sys.exit(1)

output_dir = "/home/ga/OpenToonz/output/grayscale_test"
start_time = float(sys.argv[1])

results = {
    "file_count": 0,
    "valid_files": 0,
    "fresh_files": 0,
    "avg_channel_deviation": 0.0,
    "total_size_bytes": 0,
    "dimensions": [0, 0],
    "files_analyzed": []
}

# Find images
image_files = sorted(glob.glob(os.path.join(output_dir, "*.png"))) + \
              sorted(glob.glob(os.path.join(output_dir, "*.tga")))

results["file_count"] = len(image_files)

total_dev = 0.0
analyzed_count = 0

for img_path in image_files:
    try:
        # Check freshness
        mtime = os.path.getmtime(img_path)
        size = os.path.getsize(img_path)
        results["total_size_bytes"] += size
        
        is_fresh = mtime > start_time
        if is_fresh:
            results["fresh_files"] += 1

        # Image analysis
        with Image.open(img_path) as img:
            results["dimensions"] = img.size
            img = img.convert('RGBA')
            
            # Convert to numpy for fast pixel access
            # We skip full analysis if too many files to save time, verify first 5 and random 5
            if analyzed_count < 10:
                arr = np.array(img)
                # Filter out transparent pixels (alpha == 0)
                # arr shape is (H, W, 4)
                # We care about deviation between R, G, B
                rgb = arr[:, :, :3].astype(float)
                alpha = arr[:, :, 3]
                
                # Mask for non-transparent pixels
                mask = alpha > 0
                
                if np.any(mask):
                    pixels = rgb[mask]
                    # Calculate deviation: max(rgb) - min(rgb) per pixel
                    # Ideally 0 for grayscale
                    p_max = np.max(pixels, axis=1)
                    p_min = np.min(pixels, axis=1)
                    deviation = np.mean(p_max - p_min)
                    
                    total_dev += deviation
                    analyzed_count += 1
                    
                    results["files_analyzed"].append({
                        "filename": os.path.basename(img_path),
                        "deviation": float(deviation),
                        "fresh": is_fresh
                    })
        
        results["valid_files"] += 1
            
    except Exception as e:
        print(f"Error processing {img_path}: {e}", file=sys.stderr)

if analyzed_count > 0:
    results["avg_channel_deviation"] = total_dev / analyzed_count
else:
    results["avg_channel_deviation"] = 255.0 # Worst case if no valid pixels found

# Check if app is running
try:
    stream = os.popen('pgrep -f opentoonz')
    results["app_running"] = bool(stream.read().strip())
except:
    results["app_running"] = False

# Dump to JSON
print(json.dumps(results, indent=2))
EOF

# Execute analysis
echo "Running result analysis..."
python3 /tmp/analyze_results.py "$TASK_START_TIME" > /tmp/task_result.json

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Analysis complete. JSON result:"
cat /tmp/task_result.json
echo "=== Export complete ==="