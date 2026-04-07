#!/bin/bash
echo "=== Exporting night_scene_composite_delivery result ==="

OUTPUT_DIR="/home/ga/OpenToonz/output/night_composite"
BACKGROUND_IMAGE="/home/ga/OpenToonz/backgrounds/night_city.jpg"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# Count output files (PNG/TGA)
FILE_COUNT=$(find "$OUTPUT_DIR" -maxdepth 3 \( -name "*.png" -o -name "*.tga" \) -type f 2>/dev/null | wc -l)
FILE_COUNT=${FILE_COUNT:-0}

# Count files created after task start
FILES_AFTER_START=$(find "$OUTPUT_DIR" -maxdepth 3 \( -name "*.png" -o -name "*.tga" \) -newer /tmp/task_start_timestamp -type f 2>/dev/null | wc -l)
FILES_AFTER_START=${FILES_AFTER_START:-0}

# Total output size
TOTAL_SIZE_KB=0
if [ -d "$OUTPUT_DIR" ]; then
    TOTAL_SIZE_KB=$(du -sk "$OUTPUT_DIR" 2>/dev/null | awk '{print $1}')
fi
TOTAL_SIZE_KB=${TOTAL_SIZE_KB:-0}

# Check background image exists
BACKGROUND_EXISTS="false"
if [ -f "$BACKGROUND_IMAGE" ] && [ -s "$BACKGROUND_IMAGE" ]; then
    BACKGROUND_EXISTS="true"
fi

INITIAL_COUNT=$(cat /tmp/night_composite_initial_count 2>/dev/null || echo "0")

# Analyze output images with Python
echo "Analyzing rendered frames..."
python3 << 'PYEOF' > /tmp/night_composite_analysis.json
import os
import glob
import json
import statistics

try:
    from PIL import Image, ImageFilter, ImageStat
    HAS_PIL = True
except ImportError:
    HAS_PIL = False

output_dir = "/home/ga/OpenToonz/output/night_composite"

results = {
    "img_width": 0,
    "img_height": 0,
    "avg_laplacian_var": 0.0,
    "corner_avg_brightness": 0.0,
    "center_avg_brightness": 0.0,
    "corner_edge_density": 0.0,
    "center_edge_density": 0.0,
    "frames_analyzed": 0,
    "is_blank": True,
    "has_content_difference": False
}

if not HAS_PIL:
    print(json.dumps(results))
    exit(0)

# Find PNG files
files = sorted(glob.glob(os.path.join(output_dir, "*.png")))
if not files:
    files = sorted(glob.glob(os.path.join(output_dir, "*.tga")))

if not files:
    print(json.dumps(results))
    exit(0)

# Analyze a sample of frames (first, middle, last)
sample_indices = list(set([0, len(files) // 2, len(files) - 1]))
sample_files = [files[i] for i in sorted(sample_indices) if i < len(files)]

widths = []
heights = []
corner_brights = []
center_brights = []
corner_edges = []
center_edges = []
laplacian_vars = []

for f_path in sample_files:
    try:
        img = Image.open(f_path).convert("RGB")
        w, h = img.size
        widths.append(w)
        heights.append(h)

        # Overall sharpness (Laplacian variance)
        gray = img.convert("L")
        lap = gray.filter(ImageFilter.Kernel((3, 3), (0, 1, 0, 1, -4, 1, 0, 1, 0), 1, 0))
        lap_stat = ImageStat.Stat(lap)
        laplacian_vars.append(lap_stat.var[0])

        # Corner brightness (background region)
        import numpy as np
        arr = np.array(img)
        corners = [arr[:80, :120], arr[:80, -120:], arr[-80:, :120], arr[-80:, -120:]]
        corner_mean = float(np.mean([c.mean() for c in corners]))
        corner_brights.append(corner_mean)

        # Center brightness (character region)
        center = arr[h//4:3*h//4, w//4:3*w//4]
        center_mean = float(center.mean())
        center_brights.append(center_mean)

        # Edge density in corners vs center (for blur detection)
        edges = gray.filter(ImageFilter.FIND_EDGES)
        earr = np.array(edges)
        corner_edge = float(np.mean([
            earr[:80, :120].mean(),
            earr[:80, -120:].mean(),
            earr[-80:, :120].mean(),
            earr[-80:, -120:].mean()
        ]))
        corner_edges.append(corner_edge)

        center_edge = float(earr[h//4:3*h//4, w//3:2*w//3].mean())
        center_edges.append(center_edge)

    except Exception as e:
        pass

if widths:
    results["img_width"] = widths[0]
    results["img_height"] = heights[0]
    results["frames_analyzed"] = len(widths)

if laplacian_vars:
    results["avg_laplacian_var"] = statistics.mean(laplacian_vars)

if corner_brights:
    results["corner_avg_brightness"] = statistics.mean(corner_brights)
    results["center_avg_brightness"] = statistics.mean(center_brights)
    results["is_blank"] = (results["corner_avg_brightness"] < 1.0 and results["center_avg_brightness"] < 1.0)
    results["has_content_difference"] = abs(results["center_avg_brightness"] - results["corner_avg_brightness"]) > 10

if corner_edges:
    results["corner_edge_density"] = statistics.mean(corner_edges)
    results["center_edge_density"] = statistics.mean(center_edges)

print(json.dumps(results))
PYEOF

# Check if OpenToonz is still running
APP_RUNNING=$(pgrep -f opentoonz > /dev/null && echo "true" || echo "false")

# Construct final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << RESULTEOF
{
    "file_count": $FILE_COUNT,
    "files_after_start": $FILES_AFTER_START,
    "total_size_kb": $TOTAL_SIZE_KB,
    "initial_count": $INITIAL_COUNT,
    "background_exists": $BACKGROUND_EXISTS,
    "app_running": $APP_RUNNING,
    "output_dir": "$OUTPUT_DIR",
    "task_start": $TASK_START,
    "analysis": $(cat /tmp/night_composite_analysis.json 2>/dev/null || echo '{}')
}
RESULTEOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result written to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="
