#!/bin/bash
# Export result for publication_skull_render task

echo "=== Exporting publication_skull_render result ==="

source /workspace/scripts/task_utils.sh

OUTPUT_FILE="/home/ga/Documents/skull_frontal_pub.png"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Gather file statistics using Python (in container)
# We don't do deep pixel analysis here; we let the verifier do that on the host.
# We just check basic file properties.
python3 << 'PYEOF'
import os
import json
import struct

output_path = "/home/ga/Documents/skull_frontal_pub.png"
task_start = int(os.environ.get("TASK_START", 0))

result = {
    "file_exists": False,
    "file_size_bytes": 0,
    "created_during_task": False,
    "is_png": False,
    "width": 0,
    "height": 0
}

if os.path.isfile(output_path):
    stat = os.stat(output_path)
    result["file_exists"] = True
    result["file_size_bytes"] = stat.st_size
    
    # Check creation/modification time vs task start
    # Note: st_ctime is change time on Unix, st_mtime is modification
    if stat.st_mtime > task_start:
        result["created_during_task"] = True

    # Basic PNG header check and dimension extraction
    try:
        with open(output_path, "rb") as f:
            header = f.read(24)
            if header.startswith(b"\x89PNG\r\n\x1a\n"):
                result["is_png"] = True
                # IHDR chunk starts at byte 8. Width at 16, Height at 20 (big-endian)
                # IHDR: Length(4) + ChunkType(4) + Width(4) + Height(4)
                # Header read so far: 8 magic + 4 len + 4 type + 4 width + 4 height = 24 bytes
                # Actually, standard PNG:
                # 0-7: Magic
                # 8-11: Length of IHDR (usually 13)
                # 12-15: "IHDR"
                # 16-19: Width
                # 20-23: Height
                w = struct.unpack(">I", header[16:20])[0]
                h = struct.unpack(">I", header[20:24])[0]
                result["width"] = w
                result["height"] = h
    except Exception as e:
        result["error"] = str(e)

with open("/tmp/publication_skull_render_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="