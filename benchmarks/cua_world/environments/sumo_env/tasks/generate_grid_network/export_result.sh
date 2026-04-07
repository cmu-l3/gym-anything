#!/bin/bash
echo "=== Exporting generate_grid_network task results ==="

# Record task end time
date +%s > /tmp/task_end_time.txt

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final_state.png 2>/dev/null || true

# We will use a Python script to reliably parse the XML files and extract stats, 
# storing them in a JSON file that the verifier will pull.
cat > /tmp/extract_stats.py << 'PYEOF'
import json
import os
import xml.etree.ElementTree as ET

WORK_DIR = "/home/ga/SUMO_Scenarios/grid_development"
start_time = 0.0

try:
    with open("/tmp/task_start_time.txt", "r") as f:
        start_time = float(f.read().strip())
except Exception:
    pass

def check_file(filename):
    path = os.path.join(WORK_DIR, filename)
    exists = os.path.isfile(path)
    mtime = os.path.getmtime(path) if exists else 0
    size = os.path.getsize(path) if exists else 0
    after_start = mtime > start_time if (exists and start_time > 0) else False
    return path, exists, mtime, size, after_start

result = {
    "start_time": start_time,
    "network": {},
    "routes": {},
    "config": {},
    "tripinfo": {}
}

# 1. Check Network File
path, exists, mtime, size, after_start = check_file("grid.net.xml")
result["network"] = {
    "exists": exists, "after_start": after_start, "size": size, 
    "valid": False, "junctions": 0, "speed_ok": False, "lanes_ok": False
}
if exists:
    try:
        root = ET.parse(path).getroot()
        result["network"]["valid"] = True
        junctions = [j for j in root.findall('junction') if j.get('type') not in ('internal',)]
        result["network"]["junctions"] = len(junctions)
        
        edges = [e for e in root.findall('edge') if not e.get('id', '').startswith(':')]
        for e in edges[:10]:
            lanes = e.findall('lane')
            if len(lanes) >= 2:
                result["network"]["lanes_ok"] = True
            for l in lanes:
                spd = float(l.get('speed', '0'))
                if abs(spd - 13.89) < 0.5:
                    result["network"]["speed_ok"] = True
    except Exception as e:
        result["network"]["error"] = str(e)

# 2. Check Routes File
path, exists, mtime, size, after_start = check_file("routes.rou.xml")
result["routes"] = {
    "exists": exists, "after_start": after_start, "size": size,
    "valid": False, "vehicle_count": 0
}
if exists:
    try:
        root = ET.parse(path).getroot()
        result["routes"]["valid"] = True
        vehicles = root.findall('.//vehicle') + root.findall('.//trip') + root.findall('.//flow')
        result["routes"]["vehicle_count"] = len(vehicles)
    except Exception as e:
        result["routes"]["error"] = str(e)

# 3. Check Config File
path, exists, mtime, size, after_start = check_file("grid.sumocfg")
result["config"] = {
    "exists": exists, "after_start": after_start, "size": size,
    "valid": False, "has_net": False, "has_route": False, "has_tripinfo": False
}
if exists:
    try:
        root = ET.parse(path).getroot()
        result["config"]["valid"] = True
        result["config"]["has_net"] = root.find('.//net-file') is not None
        result["config"]["has_route"] = (root.find('.//route-files') is not None or 
                                         root.find('.//route-file') is not None)
        result["config"]["has_tripinfo"] = root.find('.//tripinfo-output') is not None
    except Exception as e:
        result["config"]["error"] = str(e)

# 4. Check Tripinfo File
path, exists, mtime, size, after_start = check_file("tripinfo.xml")
result["tripinfo"] = {
    "exists": exists, "after_start": after_start, "size": size,
    "valid": False, "completed_trips": 0
}
if exists:
    try:
        root = ET.parse(path).getroot()
        result["tripinfo"]["valid"] = True
        trips = root.findall('.//tripinfo')
        completed = [t for t in trips if float(t.get('duration', '0')) > 0]
        result["tripinfo"]["completed_trips"] = len(completed)
    except Exception as e:
        result["tripinfo"]["error"] = str(e)

# Save results
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

PYEOF

# Execute the python script
python3 /tmp/extract_stats.py

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Results extracted to /tmp/task_result.json:"
cat /tmp/task_result.json
echo "=== Export complete ==="