#!/bin/bash
echo "=== Exporting historical_map_optimization_html task result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Take final screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/map_task_end.png" 2>/dev/null || true

TASK_START=$(cat /tmp/map_task_start_ts 2>/dev/null || echo "0")
ORIG_DIMS=$(cat /tmp/map_orig_dims.txt 2>/dev/null || echo "2560 1877")
ORIG_W=$(echo $ORIG_DIMS | cut -d' ' -f1)
ORIG_H=$(echo $ORIG_DIMS | cut -d' ' -f2)

HTML_FILE="/home/ga/Documents/map_viewer.html"
QUADRANTS=("map_nw.jpg" "map_ne.jpg" "map_sw.jpg" "map_se.jpg")

# Parse outputs using Python
python3 << PYEOF > /tmp/map_optimization_result.json
import json
import os
import re

result = {
    "task_start": $TASK_START,
    "orig_w": $ORIG_W,
    "orig_h": $ORIG_H,
    "html_exists": False,
    "html_size": 0,
    "html_content": "",
    "quadrants": {}
}

# 1. Inspect the Quadrant Images
quadrant_names = ["map_nw.jpg", "map_ne.jpg", "map_sw.jpg", "map_se.jpg"]
for q in quadrant_names:
    path = f"/home/ga/Documents/{q}"
    q_data = {
        "exists": False,
        "size": 0,
        "mtime": 0,
        "width": 0,
        "height": 0
    }
    
    if os.path.exists(path):
        q_data["exists"] = True
        q_data["size"] = os.path.getsize(path)
        q_data["mtime"] = os.path.getmtime(path)
        
        # Get dimensions using ImageMagick identify
        try:
            import subprocess
            dims = subprocess.check_output(['identify', '-format', '%w %h', path]).decode('utf-8').strip()
            if dims:
                q_data["width"] = int(dims.split()[0])
                q_data["height"] = int(dims.split()[1])
        except Exception:
            pass
            
    result["quadrants"][q] = q_data

# 2. Inspect the HTML file
html_path = "/home/ga/Documents/map_viewer.html"
if os.path.exists(html_path):
    result["html_exists"] = True
    result["html_size"] = os.path.getsize(html_path)
    result["html_mtime"] = os.path.getmtime(html_path)
    
    try:
        with open(html_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
            # Store up to 5000 chars to avoid massive JSON if agent did something weird
            result["html_content"] = content[:5000] 
    except Exception as e:
        result["html_content"] = f"Error reading file: {str(e)}"

print(json.dumps(result, indent=2))
PYEOF

chmod 666 /tmp/map_optimization_result.json
echo "Result saved to /tmp/map_optimization_result.json"
cat /tmp/map_optimization_result.json
echo "=== Export complete ==="