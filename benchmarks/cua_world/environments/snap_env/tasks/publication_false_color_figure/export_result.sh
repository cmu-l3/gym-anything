#!/bin/bash
echo "=== Exporting publication_false_color_figure result ==="

source /workspace/utils/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

python3 << 'PYEOF'
import os
import json
from PIL import Image

task_start = 0
if os.path.exists('/tmp/task_start_ts'):
    task_start = int(open('/tmp/task_start_ts').read().strip())

result = {
    'task_start': task_start,
    'file_found': False,
    'file_created_after_start': False,
    'file_size': 0,
    'image_width': 0,
    'image_height': 0,
    'format': ''
}

out_file = '/home/ga/snap_exports/landsat_figure.png'

if os.path.exists(out_file):
    result['file_found'] = True
    mtime = int(os.path.getmtime(out_file))
    
    if mtime > task_start:
        result['file_created_after_start'] = True
        
    result['file_size'] = os.path.getsize(out_file)
    
    try:
        # Check actual image headers
        img = Image.open(out_file)
        result['image_width'] = img.width
        result['image_height'] = img.height
        result['format'] = img.format
    except Exception as e:
        result['error'] = str(e)

with open('/tmp/publication_figure_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/publication_figure_result.json")
PYEOF

echo "=== Export Complete ==="