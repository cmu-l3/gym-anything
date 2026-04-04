#!/bin/bash
set -e
echo "=== Exporting export_axial_tiff_stack result ==="

source /workspace/scripts/task_utils.sh

# Capture final visual state
take_screenshot /tmp/task_final.png

TARGET_DIR="/home/ga/Documents/axial_tiff_stack"
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Use Python to analyze the directory contents thoroughly
python3 << PYEOF
import os
import struct
import json
import glob

target_dir = "$TARGET_DIR"
task_start = int("$TASK_START_TIME")

result = {
    "directory_exists": False,
    "file_count": 0,
    "tiff_valid_count": 0,
    "files_created_during_task": 0,
    "avg_file_size": 0,
    "non_trivial_files": 0
}

if os.path.isdir(target_dir):
    result["directory_exists"] = True
    
    # Find all files likely to be images
    files = []
    for ext in ["*.tif", "*.tiff", "*.png", "*.bmp", "*.jpg", "*.jpeg"]:
        files.extend(glob.glob(os.path.join(target_dir, ext)))
        # Case insensitive check if needed, but glob is case-sensitive on Linux usually.
        # Let's just listdir to be safe and check extensions manually or check headers.
    
    # Better approach: list all files and check headers
    all_files = [os.path.join(target_dir, f) for f in os.listdir(target_dir) if os.path.isfile(os.path.join(target_dir, f))]
    result["file_count"] = len(all_files)
    
    valid_tiffs = 0
    created_during = 0
    non_trivial = 0
    total_size = 0
    
    for fpath in all_files:
        try:
            stats = os.stat(fpath)
            size = stats.st_size
            mtime = stats.st_mtime
            
            total_size += size
            
            # Check timestamp
            if mtime > task_start:
                created_during += 1
                
            # Check size > 10KB (trivial/empty check)
            if size > 10240:
                non_trivial += 1
            
            # Check TIFF Magic Bytes
            # II (0x4949) = Little Endian, MM (0x4D4D) = Big Endian
            # Followed by 42 (0x2A00 or 0x002A)
            with open(fpath, "rb") as f:
                header = f.read(4)
                if len(header) >= 2:
                    if header.startswith(b'\x49\x49') or header.startswith(b'\x4d\x4d'):
                        # It is likely a TIFF
                        valid_tiffs += 1
                        
        except Exception as e:
            pass

    result["tiff_valid_count"] = valid_tiffs
    result["files_created_during_task"] = created_during
    result["non_trivial_files"] = non_trivial
    if len(all_files) > 0:
        result["avg_file_size"] = total_size / len(all_files)

# Write result to JSON
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)

print(json.dumps(result, indent=2))
PYEOF

# Ensure permissions for the verifier
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="