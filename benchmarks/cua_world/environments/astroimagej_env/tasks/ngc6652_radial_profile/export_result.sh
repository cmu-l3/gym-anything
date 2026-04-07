#!/bin/bash
echo "=== Exporting NGC 6652 Radial Profile Results ==="

# Final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Forward the task start time as env var to python
export TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

python3 << 'PYEOF'
import re, json, os

task_start = float(os.environ.get("TASK_START", 0))
filepath = "/home/ga/AstroImages/measurements/ngc6652_profile_results.txt"

result = {
    "task_start": task_start,
    "file_exists": False,
    "file_mtime": 0,
    "created_during_task": False,
    "center_x": None,
    "center_y": None,
    "background": None,
    "peak_brightness": None,
    "half_light_radius": None
}

if os.path.exists(filepath):
    result["file_exists"] = True
    mtime = os.path.getmtime(filepath)
    result["file_mtime"] = mtime
    result["created_during_task"] = mtime > task_start
    
    with open(filepath, "r") as f:
        content = f.read()
    
    # Tolerant regex parsing that ignores extra spaces and casing, and accepts decimals/negatives
    def extract(pattern):
        m = re.search(pattern, content, re.IGNORECASE)
        if m:
            try: return float(m.group(1))
            except: pass
        return None
        
    result["center_x"] = extract(r"center_x\s*:\s*([-+]?[0-9]*\.?[0-9]+)")
    result["center_y"] = extract(r"center_y\s*:\s*([-+]?[0-9]*\.?[0-9]+)")
    result["background"] = extract(r"background\s*:\s*([-+]?[0-9]*\.?[0-9]+)")
    result["peak_brightness"] = extract(r"peak_brightness\s*:\s*([-+]?[0-9]*\.?[0-9]+)")
    result["half_light_radius"] = extract(r"half_light_radius\s*:\s*([-+]?[0-9]*\.?[0-9]+)")

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "=== Export Complete ==="