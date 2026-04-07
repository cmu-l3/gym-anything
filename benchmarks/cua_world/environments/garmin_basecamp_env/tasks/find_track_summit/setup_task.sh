#!/bin/bash
echo "=== Setting up find_track_summit task ==="

# Clean previous task artifacts
rm -f /c/workspace/summit_report.txt 2>/dev/null || true
rm -f /c/workspace/summit_export.gpx 2>/dev/null || true
rm -f /c/workspace/ground_truth.json 2>/dev/null || true
rm -f /c/workspace/task_start_time.txt 2>/dev/null || true

# Support native Windows path formats if using pure WSL/CMD bridging
python3 -c "import os; [os.remove(f) for f in [r'C:\workspace\summit_report.txt', r'C:\workspace\summit_export.gpx', r'C:\workspace\ground_truth.json'] if os.path.exists(f)]" 2>/dev/null || true

# Record task start time for anti-gaming checks
START_TIME=$(date +%s)
echo "$START_TIME" > /tmp/task_start_time.txt
python3 -c "with open(r'C:\workspace\task_start_time.txt', 'w') as f: f.write('$START_TIME')" 2>/dev/null || true

# Compute Ground Truth dynamically from the real GPX file
cat << 'EOF' > /tmp/compute_gt.py
import xml.etree.ElementTree as ET
import json
import os

gpx_path = r"C:\workspace\data\fells_loop.gpx"
out_path = r"C:\workspace\ground_truth.json"

if not os.path.exists(gpx_path):
    # Fallback to linux path mapping if accessed from linux side
    gpx_path = "/workspace/data/fells_loop.gpx"

try:
    tree = ET.parse(gpx_path)
    root = tree.getroot()
    max_ele = -9999.0
    max_lat = max_lon = 0.0
    
    # Iterate agnostic of GPX namespace versions
    for trkpt in root.iter():
        if 'trkpt' in trkpt.tag:
            lat = float(trkpt.get('lat', 0))
            lon = float(trkpt.get('lon', 0))
            for child in trkpt:
                if 'ele' in child.tag:
                    ele = float(child.text)
                    if ele > max_ele:
                        max_ele = ele
                        max_lat = lat
                        max_lon = lon
    
    truth = {
        "max_elevation_m": max_ele,
        "summit_lat": max_lat,
        "summit_lon": max_lon
    }
    with open(out_path, "w") as f:
        json.dump(truth, f)
    print(f"Ground truth computed successfully: {truth}")
except Exception as e:
    print(f"Error computing ground truth: {e}")
EOF

python3 /tmp/compute_gt.py || python /tmp/compute_gt.py || true

# Ensure Garmin BaseCamp is running
cat << 'EOF' > /tmp/start_bc.py
import psutil
import subprocess
import time

try:
    bc_running = any("BaseCamp.exe" in p.name() for p in psutil.process_iter(['name']))
    if not bc_running:
        bc_path = r"C:\Program Files (x86)\Garmin\BaseCamp\BaseCamp.exe"
        subprocess.Popen([bc_path])
        time.sleep(10) # Give it time to boot up and load the DB
except Exception as e:
    print(f"BaseCamp check/start failed: {e}")
EOF

python3 /tmp/start_bc.py || python /tmp/start_bc.py || true

# Take initial screenshot for evidence
python3 -c "import pyautogui; pyautogui.screenshot(r'C:\workspace\task_initial.png')" 2>/dev/null || true

echo "=== Task setup complete ==="