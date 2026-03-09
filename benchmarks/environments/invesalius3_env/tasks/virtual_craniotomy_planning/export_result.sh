#!/bin/bash
echo "=== Exporting virtual_craniotomy_planning result ==="

source /workspace/scripts/task_utils.sh

SKULL_FILE="/home/ga/Documents/skull_with_defect.stl"
FLAP_FILE="/home/ga/Documents/bone_flap.stl"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_end.png

# Parse STLs using Python to get geometry counts
python3 << PYEOF
import struct
import os
import json
import time

def analyze_stl(path, start_time):
    res = {
        "exists": False,
        "size_bytes": 0,
        "triangles": 0,
        "is_binary": False,
        "created_during_task": False,
        "valid": False
    }
    
    if not os.path.exists(path):
        return res
        
    res["exists"] = True
    res["size_bytes"] = os.path.getsize(path)
    
    # Check modification time
    mtime = os.path.getmtime(path)
    if mtime > float(start_time):
        res["created_during_task"] = True

    # Try Binary STL
    try:
        if res["size_bytes"] >= 84:
            with open(path, "rb") as f:
                header = f.read(80)
                count_bytes = f.read(4)
                if len(count_bytes) == 4:
                    count = struct.unpack("<I", count_bytes)[0]
                    expected_size = 80 + 4 + count * 50
                    # Allow slight tolerance for some exporters
                    if abs(res["size_bytes"] - expected_size) < 1024:
                        res["is_binary"] = True
                        res["triangles"] = count
                        res["valid"] = True
                        return res
    except Exception:
        pass

    # Try ASCII STL
    try:
        with open(path, "r", errors="ignore") as f:
            if "solid" in f.readline().lower():
                # Count facets
                f.seek(0)
                count = 0
                for line in f:
                    if "facet normal" in line.lower():
                        count += 1
                if count > 0:
                    res["triangles"] = count
                    res["valid"] = True
    except Exception:
        pass
        
    return res

task_start = "$TASK_START"
result = {
    "skull": analyze_stl("$SKULL_FILE", task_start),
    "flap": analyze_stl("$FLAP_FILE", task_start),
    "timestamp": time.time()
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="