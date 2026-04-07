#!/bin/bash
echo "=== Exporting task results ==="

# Take final screenshot for visual reference/evidence
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Use Python to safely check files, extract image dimensions, and format JSON output
python3 << 'EOF'
import json
import os
import time

def get_mtime(path):
    try:
        return os.path.getmtime(path)
    except Exception:
        return 0

def get_dims(path):
    try:
        from PIL import Image
        with Image.open(path) as img:
            return img.width, img.height
    except Exception:
        return 0, 0

# Get task start time
start_time = 0
try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        start_time = float(f.read().strip())
except Exception:
    pass

ui_dir = '/home/ga/Documents/UI_Analysis'
dir_exists = os.path.isdir(ui_dir)

# Check Typography Data
typo_path = os.path.join(ui_dir, 'typography.txt')
typo_exists = os.path.isfile(typo_path)
typo_mtime = get_mtime(typo_path)
typo_content = ""
if typo_exists:
    try:
        with open(typo_path, 'r', errors='ignore') as f:
            typo_content = f.read()[:500] # Restrict length safely
    except Exception:
        pass

# Check Node Screenshot
node_path = os.path.join(ui_dir, 'heading_component.png')
node_exists = os.path.isfile(node_path)
node_mtime = get_mtime(node_path)
node_w, node_h = get_dims(node_path)

# Check Viewport Screenshot
view_path = os.path.join(ui_dir, 'mobile_viewport.png')
view_exists = os.path.isfile(view_path)
view_mtime = get_mtime(view_path)
view_w, view_h = get_dims(view_path)

result = {
    "task_start": start_time,
    "dir_exists": dir_exists,
    "typography": {
        "exists": typo_exists,
        "mtime": typo_mtime,
        "content": typo_content
    },
    "node_img": {
        "exists": node_exists,
        "mtime": node_mtime,
        "width": node_w,
        "height": node_h
    },
    "view_img": {
        "exists": view_exists,
        "mtime": view_mtime,
        "width": view_w,
        "height": view_h
    }
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=4)
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result payload saved."
cat /tmp/task_result.json
echo "=== Export complete ==="