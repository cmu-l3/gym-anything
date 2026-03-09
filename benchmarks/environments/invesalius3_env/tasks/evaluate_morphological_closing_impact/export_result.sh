#!/bin/bash
echo "=== Exporting evaluate_morphological_closing_impact result ==="

source /workspace/scripts/task_utils.sh

RAW_STL="/home/ga/Documents/raw_skull.stl"
CLOSED_STL="/home/ga/Documents/closed_skull.stl"

# Take final screenshot for VLM verification
take_screenshot /tmp/task_end.png

# Basic file checks in bash/python before full verification
python3 << 'PYEOF'
import os, json, struct

files = {
    "raw": "/home/ga/Documents/raw_skull.stl",
    "closed": "/home/ga/Documents/closed_skull.stl"
}

result = {
    "raw_exists": False,
    "closed_exists": False,
    "raw_size": 0,
    "closed_size": 0,
    "raw_triangles": 0,
    "closed_triangles": 0
}

def get_triangles(path):
    if not os.path.exists(path): return 0
    size = os.path.getsize(path)
    if size < 84: return 0 # Too small for binary STL
    
    # Check binary header
    try:
        with open(path, "rb") as f:
            f.read(80) # Header
            count_bytes = f.read(4)
            if len(count_bytes) == 4:
                return struct.unpack("<I", count_bytes)[0]
    except:
        pass
    return 0

for key, path in files.items():
    if os.path.isfile(path):
        result[f"{key}_exists"] = True
        result[f"{key}_size"] = os.path.getsize(path)
        result[f"{key}_triangles"] = get_triangles(path)

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="