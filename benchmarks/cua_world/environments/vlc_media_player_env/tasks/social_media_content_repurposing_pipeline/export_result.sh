#!/bin/bash
echo "=== Exporting Task Results ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Gather data using an inline Python script
# This guarantees we extract exact media properties within the container 
# using the container's ffprobe, avoiding host dependency issues in verifier.py.
python3 << 'EOF'
import json
import os
import subprocess

OUTPUT_DIR = "/home/ga/Videos/social_package"
RESULT_JSON_PATH = "/tmp/task_result.json"

try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        start_time = float(f.read().strip())
except:
    start_time = 0.0

result_data = {
    "start_time": start_time,
    "files": {},
    "manifest_data": None
}

def probe_file(filename):
    filepath = os.path.join(OUTPUT_DIR, filename)
    if not os.path.exists(filepath):
        return None
        
    mtime = os.path.getmtime(filepath)
    size = os.path.getsize(filepath)
    
    file_info = {
        "exists": True,
        "size_bytes": size,
        "mtime": mtime,
        "created_during_task": mtime > start_time,
        "has_video": False,
        "has_audio": False,
        "width": 0,
        "height": 0,
        "duration": 0.0,
        "format": "unknown"
    }
    
    # Don't try to ffprobe image files, just return existence
    if filename.endswith(".png"):
        file_info["format"] = "image"
        return file_info
        
    cmd = [
        'ffprobe', '-v', 'error', 
        '-show_entries', 'stream=codec_type,width,height', 
        '-show_entries', 'format=duration,format_name', 
        '-of', 'json', filepath
    ]
    
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        data = json.loads(res.stdout)
        
        file_info["duration"] = float(data.get('format', {}).get('duration', 0.0))
        file_info["format"] = data.get('format', {}).get('format_name', 'unknown')
        
        for stream in data.get('streams', []):
            if stream.get('codec_type') == 'video':
                file_info["has_video"] = True
                file_info["width"] = int(stream.get('width', 0))
                file_info["height"] = int(stream.get('height', 0))
            elif stream.get('codec_type') == 'audio':
                file_info["has_audio"] = True
    except Exception as e:
        file_info["error"] = str(e)
        
    return file_info

# Check all expected media deliverables
expected_files = [
    "highlight_A.mp4", "highlight_B.mp4", "highlight_C.mp4", "highlight_D.mp4",
    "vertical_A.mp4", "vertical_B.mp4", "vertical_C.mp4", "vertical_D.mp4",
    "compilation.mp4", "compilation_audio.mp3",
    "thumb_A.png", "thumb_B.png", "thumb_C.png", "thumb_D.png"
]

for f in expected_files:
    result_data["files"][f] = probe_file(f)

# Parse Manifest
manifest_path = os.path.join(OUTPUT_DIR, "manifest.json")
if os.path.exists(manifest_path):
    try:
        with open(manifest_path, 'r') as mf:
            result_data["manifest_data"] = json.load(mf)
    except Exception as e:
        result_data["manifest_data"] = {"error": "Invalid JSON"}

# Save to tmp for verifier
with open(RESULT_JSON_PATH, 'w') as f:
    json.dump(result_data, f, indent=2)

EOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Results written to /tmp/task_result.json"