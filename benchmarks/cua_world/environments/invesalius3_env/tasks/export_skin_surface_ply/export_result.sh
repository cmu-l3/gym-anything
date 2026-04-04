#!/bin/bash
echo "=== Exporting export_skin_surface_ply result ==="

source /workspace/scripts/task_utils.sh

OUTPUT_FILE="/home/ga/Documents/skin_surface.ply"
TASK_START_TIMESTAMP=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_end.png

# Analyze the PLY file using Python
python3 << PYEOF
import os
import json
import struct
import time

output_file = "$OUTPUT_FILE"
task_start = $TASK_START_TIMESTAMP

result = {
    "file_exists": False,
    "file_size_bytes": 0,
    "is_ply": False,
    "format": "unknown",
    "vertex_count": 0,
    "face_count": 0,
    "created_during_task": False,
    "header_valid": False
}

if os.path.isfile(output_file):
    result["file_exists"] = True
    stats = os.stat(output_file)
    result["file_size_bytes"] = stats.st_size
    
    # Check creation/modification time
    # Note: Linux file creation time (birthtime) is not always available, use mtime
    if stats.st_mtime > task_start:
        result["created_during_task"] = True

    try:
        with open(output_file, "rb") as f:
            # Read header (first few lines)
            header_lines = []
            while True:
                line = f.readline()
                if not line:
                    break
                header_lines.append(line)
                if line.strip() == b"end_header":
                    break
                if len(header_lines) > 100: # Safety break
                    break
            
            # Parse header
            if len(header_lines) > 0 and header_lines[0].strip() == b"ply":
                result["is_ply"] = True
                result["header_valid"] = True
                
                for line in header_lines:
                    line_str = line.decode('ascii', errors='ignore').strip()
                    if line_str.startswith("format"):
                        parts = line_str.split()
                        if len(parts) > 1:
                            result["format"] = parts[1]
                    elif line_str.startswith("element vertex"):
                        parts = line_str.split()
                        if len(parts) > 2:
                            result["vertex_count"] = int(parts[2])
                    elif line_str.startswith("element face"):
                        parts = line_str.split()
                        if len(parts) > 2:
                            result["face_count"] = int(parts[2])
            
            # Basic validation of binary vs ascii content could go here, 
            # but header parsing is usually sufficient for "is this a valid PLY".
            
    except Exception as e:
        result["error"] = str(e)

# Write result to JSON
with open("/tmp/export_ply_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

# Ensure permissions
chmod 666 /tmp/export_ply_result.json 2>/dev/null || true

echo "=== Export Complete ==="