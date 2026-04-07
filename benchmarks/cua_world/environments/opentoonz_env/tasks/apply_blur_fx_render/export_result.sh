#!/bin/bash
echo "=== Exporting apply_blur_fx_render results ==="

OUTPUT_DIR="/home/ga/OpenToonz/output/blur_fx"
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture Final Screenshot (Evidence of UI state)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Analyze Output Files
# We use an embedded Python script to analyze the images for "blurriness".
# Methodology: Calculate Laplacian Variance. 
# - High variance (>500-1000) = Sharp edges (Line art)
# - Low variance (<100-300) = Blurred
# - Near zero (<5) = Blank/Solid image (invalid)

echo "Analyzing rendered frames..."
python3 << EOF > /tmp/image_analysis.json
import os
import glob
import json
import statistics
import time

try:
    from PIL import Image, ImageFilter, ImageStat
except ImportError:
    # Fallback if PIL not installed, though it should be in env
    print(json.dumps({"error": "PIL not installed"}))
    exit(0)

output_dir = "$OUTPUT_DIR"
task_start = $TASK_START_TIME

results = {
    "files_found": 0,
    "files_valid_timestamp": 0,
    "avg_laplacian_var": 0.0,
    "avg_intensity": 0.0,
    "width": 0,
    "height": 0,
    "frames_analyzed": 0,
    "is_blank": True
}

# Find PNG files
files = sorted(glob.glob(os.path.join(output_dir, "*.png")))
results["files_found"] = len(files)

valid_files = []
for f in files:
    try:
        mtime = os.path.getmtime(f)
        if mtime > task_start:
            results["files_valid_timestamp"] += 1
            valid_files.append(f)
    except:
        pass

# Analyze a sample of valid files (first, middle, last)
sample_files = []
if valid_files:
    indices = [0, len(valid_files)//2, -1]
    # Deduplicate indices
    indices = sorted(list(set(indices)))
    sample_files = [valid_files[i] for i in indices]

variances = []
intensities = []

for f_path in sample_files:
    try:
        img = Image.open(f_path).convert('L') # Convert to grayscale
        results["width"], results["height"] = img.size
        
        # Calculate Edge Sharpness (Laplacian Variance approximation)
        # Convolve with Laplacian kernel
        laplacian_kernel = img.filter(ImageFilter.Kernel((3, 3), 
            (0, 1, 0, 1, -4, 1, 0, 1, 0), 1, 0))
        stat = ImageStat.Stat(laplacian_kernel)
        var = stat.var[0]
        variances.append(var)
        
        # Check intensity (to detect blank images)
        img_stat = ImageStat.Stat(img)
        mean_intensity = img_stat.mean[0]
        intensities.append(mean_intensity)
        
    except Exception as e:
        print(f"Error processing {f_path}: {e}")

if variances:
    results["avg_laplacian_var"] = statistics.mean(variances)
    results["avg_intensity"] = statistics.mean(intensities)
    results["frames_analyzed"] = len(variances)
    # Check if image is effectively blank (very low intensity or variance 0)
    results["is_blank"] = (results["avg_intensity"] < 1.0) or (results["avg_laplacian_var"] == 0.0)

print(json.dumps(results))
EOF

# 3. Check if OpenToonz is still running
APP_RUNNING=$(pgrep -f opentoonz > /dev/null && echo "true" || echo "false")

# 4. Construct Final Result JSON
# Merge the python analysis with shell-collected data
cat << EOF > /tmp/task_result.json
{
    "task_start": $TASK_START_TIME,
    "app_running": $APP_RUNNING,
    "analysis": $(cat /tmp/image_analysis.json)
}
EOF

# Set permissions for the verifier to read
chmod 644 /tmp/task_result.json

echo "Result generated:"
cat /tmp/task_result.json
echo "=== Export complete ==="