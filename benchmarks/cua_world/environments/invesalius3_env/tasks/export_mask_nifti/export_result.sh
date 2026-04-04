#!/bin/bash
# Export result for export_mask_nifti task

echo "=== Exporting export_mask_nifti result ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Path configuration
OUTPUT_FILE="/home/ga/Documents/bone_mask.nii.gz"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Use embedded Python to analyze the NIfTI file properties
# This checks Gzip integrity, NIfTI header, dimensions, and content presence
python3 << PYEOF
import os
import json
import struct
import gzip
import time

output_path = "$OUTPUT_FILE"
task_start = int("$TASK_START")
task_end = int("$TASK_END")

result = {
    "file_exists": False,
    "file_size_bytes": 0,
    "created_during_task": False,
    "is_gzip": False,
    "is_nifti": False,
    "dims": [0, 0, 0],
    "voxel_count_nonzero": 0,
    "parsing_error": None
}

if os.path.exists(output_path):
    result["file_exists"] = True
    stat = os.stat(output_path)
    result["file_size_bytes"] = stat.st_size
    
    # Check modification time
    # Allow a small buffer for clock skew, but generally mtime should be > task_start
    if stat.st_mtime >= task_start:
        result["created_during_task"] = True
        
    try:
        # Check Gzip magic bytes
        with open(output_path, "rb") as f:
            magic = f.read(2)
        
        if magic == b'\x1f\x8b':
            result["is_gzip"] = True
            
            # Open with gzip to check NIfTI header
            with gzip.open(output_path, "rb") as gz:
                # NIfTI-1 header is 348 bytes
                header = gz.read(348)
                
                if len(header) == 348:
                    # Check NIfTI magic string at offset 344
                    # Usually 'n+1\0' or 'n+2\0'
                    nifti_magic = header[344:348]
                    if b'n+1' in nifti_magic or b'n+2' in nifti_magic:
                        result["is_nifti"] = True
                        
                        # Parse dimensions at offset 40 (short array[8])
                        # dim[0] is number of dimensions, dim[1]..dim[7] are sizes
                        dims = struct.unpack('<8h', header[40:56])
                        # We expect 3D volume usually: dim[1], dim[2], dim[3]
                        result["dims"] = [dims[1], dims[2], dims[3]]
                        
                        # Rudimentary content check
                        # Read chunk of data to see if it's not all zeros
                        # Note: This doesn't decode the whole image to save time/memory,
                        # just checks a chunk for non-zero bytes to ensure it's a mask.
                        chunk = gz.read(100000)
                        non_zeros = 0
                        for b in chunk:
                            if b != 0:
                                non_zeros += 1
                        result["voxel_count_nonzero"] = non_zeros
                        
                        # If simple read found nothing, try to read more if file is small enough
                        # or rely on file size
    except Exception as e:
        result["parsing_error"] = str(e)

# Output JSON
with open("/tmp/export_mask_nifti_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="