#!/bin/bash
echo "=== Exporting import_correct_dicom_series result ==="

source /workspace/scripts/task_utils.sh

OUTPUT_FILE="/home/ga/Documents/axial_skull.stl"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Analyze Output File (STL)
python3 << EOF
import os
import json
import struct
import time

output_path = "$OUTPUT_FILE"
task_start = $TASK_START
result = {
    "output_exists": False,
    "file_created_during_task": False,
    "file_size": 0,
    "triangle_count": 0,
    "is_binary_stl": False,
    "error": None
}

if os.path.exists(output_path):
    result["output_exists"] = True
    stats = os.stat(output_path)
    result["file_size"] = stats.st_size
    
    # Check creation time
    if stats.st_mtime > task_start:
        result["file_created_during_task"] = True
        
    # Parse STL to count triangles
    try:
        # Check if binary STL (80 byte header + 4 byte count)
        if stats.st_size >= 84:
            with open(output_path, 'rb') as f:
                header = f.read(80)
                count_bytes = f.read(4)
                tri_count = struct.unpack('<I', count_bytes)[0]
                
                # Verify size matches count (50 bytes per triangle)
                expected_size = 84 + (tri_count * 50)
                # Allow some tolerance for file padding or extra data
                if abs(stats.st_size - expected_size) < 1024:
                    result["is_binary_stl"] = True
                    result["triangle_count"] = tri_count
                else:
                    # Might be ASCII
                    result["error"] = "Size mismatch for binary STL"
        
        # Fallback check for ASCII if binary check failed
        if not result["is_binary_stl"]:
            with open(output_path, 'r', errors='ignore') as f:
                if f.read(5).lower() == 'solid':
                    # Count facets
                    f.seek(0)
                    content = f.read()
                    result["triangle_count"] = content.count('facet normal')
    except Exception as e:
        result["error"] = str(e)

# Save result
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
EOF

# Permissions
chmod 666 /tmp/task_result.json

echo "Result JSON:"
cat /tmp/task_result.json
echo "=== Export Complete ==="