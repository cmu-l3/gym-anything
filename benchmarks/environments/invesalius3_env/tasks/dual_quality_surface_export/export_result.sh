#!/bin/bash
echo "=== Exporting dual_quality_surface_export result ==="

source /workspace/scripts/task_utils.sh

# Capture final state
take_screenshot /tmp/task_final.png

# Paths
BEST_PATH="/home/ga/Documents/skull_best.stl"
LOWRES_PATH="/home/ga/Documents/skull_lowres.stl"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Analyze files using Python
# We check: existence, valid STL header, triangle count, modification time, file hash (for identity check)
python3 << PYEOF
import struct
import os
import json
import hashlib
import time

def analyze_stl(path):
    info = {
        "exists": False,
        "size": 0,
        "mtime": 0,
        "valid": False,
        "binary": False,
        "triangles": 0,
        "hash": ""
    }
    
    if not os.path.exists(path):
        return info
        
    info["exists"] = True
    info["size"] = os.path.getsize(path)
    info["mtime"] = os.path.getmtime(path)
    
    # Calculate hash to detect if files are identical
    try:
        with open(path, "rb") as f:
            file_data = f.read()
            info["hash"] = hashlib.md5(file_data).hexdigest()
            
        # Check Binary STL (80 byte header + 4 byte count)
        if info["size"] >= 84:
            with open(path, "rb") as f:
                header = f.read(80)
                count_bytes = f.read(4)
                count = struct.unpack("<I", count_bytes)[0]
                expected_size = 84 + (count * 50)
                
                # Allow a small buffer for extra data at EOF, but standard binary STL is exact
                if abs(info["size"] - expected_size) < 1024:
                    info["binary"] = True
                    info["valid"] = True
                    info["triangles"] = count
                    return info

        # Check ASCII STL (fallback)
        try:
            with open(path, "r", encoding="utf-8", errors="ignore") as f:
                head = f.read(1024).lstrip()
                if head.startswith("solid"):
                    f.seek(0)
                    # Rough count of facets
                    content = f.read()
                    facets = content.count("facet normal")
                    if facets > 0:
                        info["binary"] = False
                        info["valid"] = True
                        info["triangles"] = facets
        except:
            pass
            
    except Exception as e:
        info["error"] = str(e)
        
    return info

results = {
    "task_start_time": $TASK_START,
    "best": analyze_stl("$BEST_PATH"),
    "lowres": analyze_stl("$LOWRES_PATH"),
    "timestamp": time.time()
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(results, f, indent=2)
    
print(json.dumps(results, indent=2))
PYEOF

echo "=== Export Complete ==="