#!/bin/bash
echo "=== Exporting isolate_largest_surface result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Analyze the STL files using Python
# We use a python script to parse the binary STL headers and count triangles accurately
python3 << 'PYEOF'
import struct
import os
import json
import hashlib

def analyze_stl(path, task_start_time):
    info = {
        "exists": False,
        "valid": False,
        "is_binary": False,
        "triangle_count": 0,
        "file_size": 0,
        "modified_after_start": False,
        "sha256": None
    }
    
    if not os.path.exists(path):
        return info
        
    info["exists"] = True
    info["file_size"] = os.path.getsize(path)
    
    # Check timestamp
    mtime = os.path.getmtime(path)
    if mtime > task_start_time:
        info["modified_after_start"] = True
        
    # Compute Hash
    try:
        with open(path, "rb") as f:
            file_data = f.read()
            info["sha256"] = hashlib.sha256(file_data).hexdigest()
    except Exception:
        pass

    # Parse STL
    try:
        with open(path, "rb") as f:
            header = f.read(80)
            count_bytes = f.read(4)
            
            # Check for binary STL
            # Binary STL file size = 80 + 4 + (count * 50)
            if len(count_bytes) == 4:
                count = struct.unpack("<I", count_bytes)[0]
                expected_size = 84 + (count * 50)
                
                # Allow for some padding bytes at end of file, or exact match
                if abs(info["file_size"] - expected_size) < 1024:
                    info["is_binary"] = True
                    info["triangle_count"] = count
                    info["valid"] = True
                    return info

        # Fallback to ASCII check if binary check failed
        # (Though task asks for binary, we can be lenient if geometry is correct)
        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            head = f.readline().strip()
            if head.startswith("solid"):
                # It's likely ASCII, count facets
                # This is slow for large files, but acceptable for grading
                f.seek(0)
                content = f.read()
                info["triangle_count"] = content.count("facet normal")
                if info["triangle_count"] > 0:
                    info["valid"] = True
                    info["is_binary"] = False
                    
    except Exception as e:
        print(f"Error parsing {path}: {e}")
        
    return info

# Get task start time from bash variable passed to python
task_start_str = os.environ.get("TASK_START", "0")
try:
    task_start = float(task_start_str)
except:
    task_start = 0

raw_path = "/home/ga/Documents/bone_raw.stl"
cleaned_path = "/home/ga/Documents/bone_cleaned.stl"

res_raw = analyze_stl(raw_path, task_start)
res_cleaned = analyze_stl(cleaned_path, task_start)

final_result = {
    "raw": res_raw,
    "cleaned": res_cleaned,
    "screenshot_path": "/tmp/task_final.png",
    "timestamp": task_start
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(final_result, f, indent=2)

print(json.dumps(final_result, indent=2))
PYEOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="