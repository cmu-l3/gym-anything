#!/bin/bash
# Export result script for Mobile Viewport Screenshot Audit

source /workspace/scripts/task_utils.sh

echo "=== Exporting Mobile Viewport Audit Result ==="

take_screenshot /tmp/task_end_screenshot.png

EXPORT_BASE="/home/ga/Documents/SEO/exports"
TARGET_DIR="$EXPORT_BASE/mobile_screenshots"
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")

# Initialize result variables
FOLDER_EXISTS="false"
IMAGE_COUNT=0
AVG_WIDTH=0
VALID_IMAGES=0
TIMESTAMPS_VALID="false"

if [ -d "$TARGET_DIR" ]; then
    FOLDER_EXISTS="true"
    
    # Python script to check image dimensions using standard struct library (no PIL dependency required)
    # This handles PNG and JPG which are the standard exports
    python3 -c "
import os
import struct
import json
import glob

def get_image_info(file_path):
    with open(file_path, 'rb') as f:
        data = f.read(24)
        if data.startswith(b'\x89PNG\r\n\x1a\n'):
            # PNG: Width is at offset 16, 4 bytes big-endian
            w, h = struct.unpack('>II', data[16:24])
            return 'PNG', w, h
        elif data.startswith(b'\xff\xd8'):
            # JPEG: Scan for SOF0 marker
            f.seek(0)
            f.read(2)
            b = f.read(1)
            while b and b != b'\xda':
                while b != b'\xff': b = f.read(1)
                while b == b'\xff': b = f.read(1)
                if 0xc0 <= ord(b) <= 0xc3:
                    f.read(3)
                    h, w = struct.unpack('>HH', f.read(4))
                    return 'JPG', w, h
                else:
                    f.read(int(struct.unpack('>H', f.read(2))[0]) - 2)
                b = f.read(1)
    return None, 0, 0

target_dir = '$TARGET_DIR'
task_start = $TASK_START_EPOCH
images = []
valid_count = 0
total_width = 0

# Scan for common image extensions
files = glob.glob(os.path.join(target_dir, '*.[pjPJ]*')) # matches .png, .jpg, .jpeg
files = [f for f in files if f.lower().endswith(('.png', '.jpg', '.jpeg'))]

for p in files:
    try:
        mtime = os.path.getmtime(p)
        if mtime > task_start:
            fmt, w, h = get_image_info(p)
            if fmt:
                images.append({'path': p, 'width': w, 'height': h, 'format': fmt})
                total_width += w
                valid_count += 1
    except Exception as e:
        print(f'Error processing {p}: {e}')

avg_width = total_width / valid_count if valid_count > 0 else 0

result = {
    'folder_exists': True,
    'image_count': len(images),
    'valid_images_count': valid_count,
    'average_width': avg_width,
    'images_info': images,
    'timestamps_valid': valid_count > 0
}

with open('/tmp/image_analysis.json', 'w') as f:
    json.dump(result, f)
"
else
    # Check if images were dumped directly in export base (common mistake)
    # We won't give full points but we can detect it
    echo "{ \"folder_exists\": false, \"image_count\": 0 }" > /tmp/image_analysis.json
fi

# Read python analysis result
if [ -f "/tmp/image_analysis.json" ]; then
    cat /tmp/image_analysis.json > /tmp/task_result.json
else
    echo "{ \"error\": \"Analysis script failed\" }" > /tmp/task_result.json
fi

# Add screenshot path to result
# Use jq if available, otherwise simple appending is risky with json syntax. 
# We'll rely on the python script output structure.

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export Complete ==="