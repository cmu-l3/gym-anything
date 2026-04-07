#!/bin/bash
echo "=== Exporting cartographic_map_preparation result ==="

source /workspace/utils/task_utils.sh 2>/dev/null || true

# Take final screenshot
if type take_screenshot &>/dev/null; then
    take_screenshot /tmp/task_end_screenshot.png
else
    DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true
fi

# We use python3 with PIL to reliably check file properties and dimensions
python3 << 'PYEOF'
import os, json
from PIL import Image
Image.MAX_IMAGE_PIXELS = None

task_start = 0
ts_file = '/tmp/task_start_ts'
if os.path.exists(ts_file):
    try:
        task_start = int(open(ts_file).read().strip())
    except:
        pass

orig_w, orig_h = 10980, 10980
if os.path.exists('/tmp/orig_dims.txt'):
    try:
        w, h = open('/tmp/orig_dims.txt').read().strip().split(',')
        orig_w, orig_h = int(w), int(h)
    except:
        pass

result = {
    'task_start': task_start,
    'png_found': False,
    'png_created_after_start': False,
    'png_size': 0,
    'tif_found': False,
    'tif_created_after_start': False,
    'tif_size': 0,
    'orig_width': orig_w,
    'orig_height': orig_h,
    'subset_width': 0,
    'subset_height': 0
}

png_path = '/home/ga/snap_exports/press_release_map.png'
if os.path.exists(png_path):
    result['png_found'] = True
    result['png_size'] = os.path.getsize(png_path)
    if int(os.path.getmtime(png_path)) > task_start:
        result['png_created_after_start'] = True

tif_path = '/home/ga/snap_exports/subset_tci.tif'
if os.path.exists(tif_path):
    result['tif_found'] = True
    result['tif_size'] = os.path.getsize(tif_path)
    if int(os.path.getmtime(tif_path)) > task_start:
        result['tif_created_after_start'] = True
    try:
        img = Image.open(tif_path)
        result['subset_width'] = img.width
        result['subset_height'] = img.height
    except Exception as e:
        print(f"Error reading tif dims: {e}")

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/task_result.json")
PYEOF

echo "=== Export Complete ==="