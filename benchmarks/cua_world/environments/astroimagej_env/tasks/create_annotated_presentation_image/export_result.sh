#!/bin/bash
echo "=== Exporting task results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/AstroImages/processed/uit_presentation.png"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Extract image info using Python and PIL
python3 -c "
import json
import os
import sys

output_path = '$OUTPUT_PATH'
task_start = int('$TASK_START')

result = {
    'output_exists': False,
    'file_created_during_task': False,
    'size_bytes': 0,
    'image_mode': 'unknown',
    'image_format': 'unknown',
    'width': 0,
    'height': 0
}

if os.path.exists(output_path):
    result['output_exists'] = True
    stat = os.stat(output_path)
    result['size_bytes'] = stat.st_size
    
    if stat.st_mtime >= task_start:
        result['file_created_during_task'] = True
        
    try:
        from PIL import Image
        with Image.open(output_path) as img:
            result['image_mode'] = img.mode
            result['image_format'] = img.format
            result['width'] = img.width
            result['height'] = img.height
    except Exception as e:
        result['error'] = str(e)

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
"

# Handle permissions
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json:"
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="