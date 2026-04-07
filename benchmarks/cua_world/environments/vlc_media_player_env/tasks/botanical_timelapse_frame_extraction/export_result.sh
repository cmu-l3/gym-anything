#!/bin/bash
echo "=== Exporting Botanical Timelapse Task Results ==="

# Copy the generated manifest
cp /home/ga/Documents/manifest.json /tmp/manifest.json 2>/dev/null || true

# Extract robust metadata internally via Python so the verifier doesn't depend on host tools
# This extracts timestamps, image file sizes, and full ffprobe JSON structures for verification
python3 << 'PYEOF'
import os, json, subprocess

def get_mtime(path):
    return int(os.path.getmtime(path)) if os.path.exists(path) else 0

def probe(path):
    if not os.path.exists(path): return {}
    try:
        res = subprocess.run(['ffprobe', '-v', 'error', '-show_format', '-show_streams', '-of', 'json', path], capture_output=True, text=True)
        return json.loads(res.stdout)
    except:
        return {}

# Inventory the extracted PNG frames
frames = []
frames_dir = "/home/ga/Pictures/bloom_frames"
if os.path.isdir(frames_dir):
    for f in os.listdir(frames_dir):
        if f.lower().endswith('.png'):
            path = os.path.join(frames_dir, f)
            frames.append({"name": f, "size": os.path.getsize(path)})

# Read task start time
try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        task_start = int(f.read().strip())
except:
    task_start = 0

data = {
    "task_start_time": task_start,
    "master_mtime": get_mtime("/home/ga/Videos/bloom_clips/peak_bloom_master.mp4"),
    "web_mtime": get_mtime("/home/ga/Videos/bloom_clips/peak_bloom_web.webm"),
    "manifest_mtime": get_mtime("/home/ga/Documents/manifest.json"),
    "frames": frames,
    "master_info": probe("/home/ga/Videos/bloom_clips/peak_bloom_master.mp4"),
    "web_info": probe("/home/ga/Videos/bloom_clips/peak_bloom_web.webm")
}

with open('/tmp/export_metadata.json', 'w') as f:
    json.dump(data, f)
PYEOF

chmod 666 /tmp/export_metadata.json /tmp/manifest.json 2>/dev/null || true

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

echo "=== Export complete ==="