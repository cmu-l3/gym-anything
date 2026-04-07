#!/bin/bash
echo "=== Exporting property_listing_video_assembly result ==="

# Take final evidence screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Run inline Python script to extract robust file information programmatically.
# Outputting stats locally inside the container prevents massive file copying 
# and dependency mismatches during Host/Verifier phase.
cat << 'EOF' > /tmp/extract_info.py
import json, os, subprocess

output_dir = "/home/ga/Videos/listing_output"
try:
    with open("/tmp/task_start_time.txt", "r") as f:
        task_start = int(f.read().strip())
except:
    task_start = 0

files_to_check = [
    "listing_master.mp4",
    "listing_mobile.mp4",
    "listing_square.mp4",
    "listing_email.mp4",
    "listing_thumbnail.jpg",
    "manifest.json"
]

result = {
    "task_start": task_start,
    "files": {},
    "agent_manifest": None
}

for fname in files_to_check:
    path = os.path.join(output_dir, fname)
    finfo = {"exists": False}
    if os.path.exists(path):
        stat = os.stat(path)
        finfo["exists"] = True
        finfo["size_bytes"] = stat.st_size
        finfo["mtime"] = stat.st_mtime
        finfo["created_during_task"] = stat.st_mtime > task_start
        
        if fname.endswith(".mp4"):
            try:
                cmd = ['ffprobe', '-v', 'error', '-show_entries', 'stream=codec_name,width,height,codec_type', '-show_entries', 'format=duration', '-of', 'json', path]
                res = subprocess.run(cmd, capture_output=True, text=True)
                data = json.loads(res.stdout)
                finfo["duration"] = float(data.get('format', {}).get('duration', 0))
                for s in data.get('streams', []):
                    if s.get('codec_type') == 'video':
                        finfo['v_codec'] = s.get('codec_name', '').lower()
                        finfo['width'] = int(s.get('width', 0))
                        finfo['height'] = int(s.get('height', 0))
                    elif s.get('codec_type') == 'audio':
                        finfo['a_codec'] = s.get('codec_name', '').lower()
                        finfo['has_audio'] = True
            except Exception as e:
                finfo["error"] = str(e)
        elif fname.endswith(".jpg"):
            try:
                from PIL import Image
                with Image.open(path) as img:
                    finfo['width'], finfo['height'] = img.size
                    finfo['format'] = img.format
            except Exception as e:
                finfo["error"] = str(e)
    result["files"][fname] = finfo

manifest_path = os.path.join(output_dir, "manifest.json")
if result["files"]["manifest.json"]["exists"]:
    try:
        with open(manifest_path, 'r') as f:
            result["agent_manifest"] = json.load(f)
    except:
        result["agent_manifest"] = "invalid_json"

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)
EOF

python3 /tmp/extract_info.py
chmod 666 /tmp/task_result.json

echo "Result JSON written to /tmp/task_result.json."
echo "=== Export complete ==="