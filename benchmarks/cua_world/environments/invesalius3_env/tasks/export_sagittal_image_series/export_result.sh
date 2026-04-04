#!/bin/bash
echo "=== Exporting export_sagittal_image_series result ==="

source /workspace/scripts/task_utils.sh

OUTPUT_DIR="/home/ga/Documents/sagittal_series"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Take final screenshot for VLM verification
take_screenshot /tmp/task_end.png

# Use Python to analyze the output directory robustly
python3 << PYEOF
import os
import json
import struct
import glob
import time

output_dir = "$OUTPUT_DIR"
task_start_time = $TASK_START
result = {
    "dir_exists": False,
    "file_count": 0,
    "valid_png_count": 0,
    "files_created_during_task": 0,
    "avg_aspect_ratio": 1.0,
    "is_square": True,
    "sample_dims": [0, 0]
}

if os.path.isdir(output_dir):
    result["dir_exists"] = True
    
    # Get all PNG files
    files = glob.glob(os.path.join(output_dir, "*.png"))
    result["file_count"] = len(files)
    
    valid_pngs = 0
    new_files = 0
    total_aspect = 0.0
    dims_checked = 0
    
    # Check a sample of files (first 10 and last 10 to be efficient)
    sample_files = files[:10] + files[-10:] if len(files) > 20 else files
    
    for fpath in sample_files:
        try:
            # Check timestamp
            mtime = os.path.getmtime(fpath)
            if mtime > task_start_time:
                new_files += 1
            
            # Parse PNG header manually to get dimensions
            # PNG signature: 8 bytes
            # IHDR chunk: 4 bytes length, 4 bytes type, width (4), height (4)
            with open(fpath, 'rb') as f:
                sig = f.read(8)
                if sig == b'\x89PNG\r\n\x1a\n':
                    valid_pngs += 1
                    
                    # Read IHDR
                    # Skip length (4) and chunk type (4) -> read 8 bytes
                    f.seek(16)
                    width_bytes = f.read(4)
                    height_bytes = f.read(4)
                    
                    width = struct.unpack(">I", width_bytes)[0]
                    height = struct.unpack(">I", height_bytes)[0]
                    
                    if width > 0 and height > 0:
                        ratio = float(width) / float(height)
                        total_aspect += ratio
                        dims_checked += 1
                        result["sample_dims"] = [width, height]
        except Exception as e:
            pass
            
    # Extrapolate counts if we sampled
    if len(files) > 0 and len(sample_files) > 0:
        result["valid_png_count"] = int(valid_pngs * (len(files) / len(sample_files)))
        result["files_created_during_task"] = int(new_files * (len(files) / len(sample_files)))
        
        if dims_checked > 0:
            result["avg_aspect_ratio"] = total_aspect / dims_checked
            # Allow small tolerance for floating point 1.0
            result["is_square"] = (0.98 < result["avg_aspect_ratio"] < 1.02)

with open("/tmp/export_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="