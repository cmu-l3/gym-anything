#!/bin/bash
# Export result for export_axial_mip_image task

echo "=== Exporting export_axial_mip_image result ==="

source /workspace/scripts/task_utils.sh

OUTPUT_FILE="/home/ga/Documents/axial_mip.png"
TASK_START_TIMESTAMP=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Take final screenshot of the UI state
take_screenshot /tmp/task_end.png

# Analyze output file using Python
python3 << PYEOF
import os
import json
import time
import struct

output_file = "$OUTPUT_FILE"
task_start = int("$TASK_START_TIMESTAMP")

result = {
    "file_exists": False,
    "file_size_bytes": 0,
    "is_png": False,
    "width": 0,
    "height": 0,
    "created_during_task": False,
    "app_running": False
}

# Check file existence and properties
if os.path.isfile(output_file):
    result["file_exists"] = True
    stat = os.stat(output_file)
    result["file_size_bytes"] = stat.st_size
    
    # Check timestamp (modification time > task start)
    if stat.st_mtime > task_start:
        result["created_during_task"] = True
        
    # Check PNG header and dimensions
    try:
        with open(output_file, "rb") as f:
            header = f.read(24)
            # PNG signature: 89 50 4E 47 0D 0A 1A 0A
            if header.startswith(b"\x89PNG\r\n\x1a\n"):
                result["is_png"] = True
                # IHDR chunk starts at byte 8, width at 16, height at 20 (big-endian 4 bytes)
                w, h = struct.unpack(">II", header[16:24])
                result["width"] = w
                result["height"] = h
    except Exception as e:
        result["error"] = str(e)

# Check if InVesalius is still running
try:
    # simple check via pgrep
    ret = os.system("pgrep -f invesalius > /dev/null")
    if ret == 0:
        result["app_running"] = True
except:
    pass

# Save to JSON
with open("/tmp/export_axial_mip_image_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="