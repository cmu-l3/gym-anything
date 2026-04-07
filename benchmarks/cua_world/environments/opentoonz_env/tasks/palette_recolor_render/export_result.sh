#!/bin/bash
echo "=== Exporting palette_recolor_render result ==="

# Configuration
OUTPUT_DIR="/home/ga/OpenToonz/output/recolor"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULT_JSON="/tmp/task_result.json"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Analyze results using Python
# We use Python here because bash is bad at image processing
# We will output a JSON structure
python3 -c "
import os
import json
import glob
import sys
from PIL import Image

output_dir = '$OUTPUT_DIR'
task_start = $TASK_START
target_rgb = (255, 102, 0) # Orange #FF6600
tolerance = 40 # Allow some compression artifacts/rendering differences

result = {
    'output_exists': False,
    'file_count': 0,
    'files_created_during_task': 0,
    'avg_orange_pixels': 0,
    'max_orange_pixels': 0,
    'total_size_kb': 0,
    'valid_format': False
}

if os.path.isdir(output_dir):
    result['output_exists'] = True
    
    # Find images
    files = glob.glob(os.path.join(output_dir, '*.png')) + \
            glob.glob(os.path.join(output_dir, '*.tga')) + \
            glob.glob(os.path.join(output_dir, '*.tif'))
    
    result['file_count'] = len(files)
    
    if files:
        result['valid_format'] = True
        
        # Check timestamps and size
        new_files = 0
        total_size = 0
        for f in files:
            mtime = os.path.getmtime(f)
            if mtime > task_start:
                new_files += 1
            total_size += os.path.getsize(f)
        
        result['files_created_during_task'] = new_files
        result['total_size_kb'] = total_size / 1024.0
        
        # Analyze Color Content
        # We sample up to 5 files to save time
        sample_files = files[:5]
        orange_counts = []
        
        for f_path in sample_files:
            try:
                img = Image.open(f_path).convert('RGB')
                # Simple pixel iteration (slow but fine for small sample)
                # Optimization: resize strictly for color checking if image is huge
                img.thumbnail((400, 400)) 
                
                width, height = img.size
                pixels = img.load()
                
                count = 0
                for x in range(width):
                    for y in range(height):
                        r, g, b = pixels[x, y]
                        # Check distance to target orange
                        dist = abs(r - target_rgb[0]) + abs(g - target_rgb[1]) + abs(b - target_rgb[2])
                        if dist < tolerance:
                            count += 1
                
                # Normalize count back to roughly original resolution scale if we resized?
                # Actually, raw count on thumbnail is enough to prove existence.
                # If we have > 50 pixels on a 400x400 thumb, that's significant.
                orange_counts.append(count)
            except Exception as e:
                print(f'Error processing {f_path}: {e}', file=sys.stderr)
        
        if orange_counts:
            result['avg_orange_pixels'] = sum(orange_counts) / len(orange_counts)
            result['max_orange_pixels'] = max(orange_counts)

print(json.dumps(result))
" > "$RESULT_JSON"

# Ensure permissions
chmod 666 "$RESULT_JSON" 2>/dev/null || true

echo "Analysis complete. Result:"
cat "$RESULT_JSON"
echo "=== Export complete ==="