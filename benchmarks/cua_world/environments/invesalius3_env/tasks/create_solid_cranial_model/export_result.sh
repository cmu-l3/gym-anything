#!/bin/bash
# Export result for create_solid_cranial_model task

echo "=== Exporting create_solid_cranial_model result ==="

source /workspace/scripts/task_utils.sh

OUTPUT_FILE="/home/ga/Documents/solid_cranium.stl"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_end.png

# Check file status using Python to generate a JSON report
python3 << PYEOF
import os
import json
import struct

output_file = "$OUTPUT_FILE"
task_start = $TASK_START
result = {
    "file_exists": False,
    "file_size_bytes": 0,
    "file_created_during_task": False,
    "is_binary_stl": False,
    "header_info": "None"
}

if os.path.isfile(output_file):
    stats = os.stat(output_file)
    result["file_exists"] = True
    result["file_size_bytes"] = stats.st_size
    
    # Check modification time against task start
    if stats.st_mtime > task_start:
        result["file_created_during_task"] = True
        
    # Basic binary STL check (size = 80 + 4 + 50*N)
    if stats.st_size >= 84:
        try:
            with open(output_file, "rb") as f:
                header = f.read(80)
                count_bytes = f.read(4)
                if len(count_bytes) == 4:
                    num_triangles = struct.unpack("<I", count_bytes)[0]
                    expected_size = 84 + (num_triangles * 50)
                    if abs(expected_size - stats.st_size) < 100: # Allow small padding tolerance
                        result["is_binary_stl"] = True
                        result["triangle_count"] = num_triangles
        except Exception as e:
            result["error"] = str(e)

with open("/tmp/create_solid_cranial_model_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

# Ensure permissions so the host can copy it (if running as root in container)
chmod 644 /tmp/create_solid_cranial_model_result.json 2>/dev/null || true
if [ -f "$OUTPUT_FILE" ]; then
    chmod 644 "$OUTPUT_FILE" 2>/dev/null || true
fi

echo "=== Export Complete ==="