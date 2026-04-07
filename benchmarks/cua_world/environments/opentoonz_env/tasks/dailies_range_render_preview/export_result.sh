#!/bin/bash
echo "=== Exporting dailies_range_render_preview result ==="

# Configuration
OUTPUT_DIR="/home/ga/OpenToonz/output/dailies"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
EXPECTED_START=5
EXPECTED_END=15

# 1. Take Final Screenshot
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || true

# 2. Analyze Output Files
# We expect files like dwanko_run.0005.png, dwanko_run.0006.png, etc.
# Python script to analyze the directory robustly
python3 -c "
import os
import re
import json
import sys
from PIL import Image

output_dir = '$OUTPUT_DIR'
task_start_ts = float($TASK_START)
expected_start = $EXPECTED_START
expected_end = $EXPECTED_END

result = {
    'files_found': [],
    'frames_indices': [],
    'extra_frames_indices': [],
    'missing_frames_indices': [],
    'resolution': [0, 0],
    'resolution_consistent': True,
    'files_fresh': True,
    'total_size_bytes': 0,
    'valid_image_format': False
}

if not os.path.exists(output_dir):
    print(json.dumps(result))
    sys.exit(0)

# Regex to capture frame number (usually suffix before extension)
# Matches: name.0001.png or name0001.png
frame_pattern = re.compile(r'.*[._-](\d+)\.(png|tga|tif|jpg)$', re.IGNORECASE)

files = sorted([f for f in os.listdir(output_dir) if f.lower().endswith(('.png', '.tga', '.tif', '.jpg'))])
result['files_found'] = files

width_set = set()
height_set = set()

for f in files:
    path = os.path.join(output_dir, f)
    
    # Check timestamp
    mtime = os.path.getmtime(path)
    if mtime < task_start_ts:
        result['files_fresh'] = False
    
    # Check size
    result['total_size_bytes'] += os.path.getsize(path)
    
    # Parse frame number
    match = frame_pattern.match(f)
    if match:
        frame_num = int(match.group(1))
        
        # Check if in target range
        if expected_start <= frame_num <= expected_end:
            result['frames_indices'].append(frame_num)
        else:
            result['extra_frames_indices'].append(frame_num)
            
        # Check Image Properties (only check a few to save time, or all if few)
        if len(width_set) == 0 or frame_num == expected_start: # Check first found
            try:
                with Image.open(path) as img:
                    width_set.add(img.width)
                    height_set.add(img.height)
                    if img.format:
                        result['valid_image_format'] = True
            except Exception:
                pass

# Determine missing frames
found_set = set(result['frames_indices'])
target_set = set(range(expected_start, expected_end + 1))
result['missing_frames_indices'] = list(target_set - found_set)

# Resolution info
if len(width_set) == 1 and len(height_set) == 1:
    result['resolution'] = [list(width_set)[0], list(height_set)[0]]
elif len(width_set) > 1:
    result['resolution_consistent'] = False
    result['resolution'] = [list(width_set)[0], list(height_set)[0]] # Just report one

print(json.dumps(result))
" > /tmp/analysis_result.json

# 3. Create Final Result JSON
# Merge the python analysis with bash info
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "timestamp": "$(date -Iseconds)",
    "analysis": $(cat /tmp/analysis_result.json)
}
EOF

# Safe file permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="