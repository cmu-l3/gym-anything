#!/bin/bash
# Export results for stopmotion_assembly_pipeline task
set -e

echo "=== Exporting task results ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# We will use Python to safely parse all media files and dump a JSON.
# This avoids fragile bash string manipulation and captures everything needed.

python3 << 'EOF'
import json
import os
import subprocess

def get_media_info(path):
    if not os.path.exists(path):
        return {"exists": False}
    
    mtime = os.path.getmtime(path)
    size = os.path.getsize(path)
    
    info = {
        "exists": True,
        "mtime": mtime,
        "size": size,
        "width": 0,
        "height": 0,
        "fps": 0.0,
        "duration": 0.0,
        "codec": "",
        "audio_streams": 0
    }
    
    try:
        cmd = ['ffprobe', '-v', 'quiet', '-print_format', 'json', '-show_format', '-show_streams', path]
        res = subprocess.check_output(cmd, timeout=10)
        data = json.loads(res)
        
        vstreams = [s for s in data.get('streams', []) if s.get('codec_type') == 'video']
        astreams = [s for s in data.get('streams', []) if s.get('codec_type') == 'audio']
        
        if vstreams:
            v = vstreams[0]
            info["width"] = v.get("width", 0)
            info["height"] = v.get("height", 0)
            info["codec"] = v.get("codec_name", "")
            
            fps_str = v.get("r_frame_rate", "0/1")
            try:
                num, den = map(int, fps_str.split('/'))
                info["fps"] = num / den if den > 0 else 0.0
            except:
                pass
                
        dur = data.get("format", {}).get("duration", 0)
        if dur:
            info["duration"] = float(dur)
            
        info["audio_streams"] = len(astreams)
        
    except Exception as e:
        info["error"] = str(e)
        
    return info

def get_image_info(path):
    if not os.path.exists(path):
        return {"exists": False}
    
    info = {
        "exists": True,
        "mtime": os.path.getmtime(path),
        "size": os.path.getsize(path),
        "width": 0,
        "height": 0
    }
    
    try:
        # Try PIL first
        from PIL import Image
        with Image.open(path) as im:
            info["width"] = im.width
            info["height"] = im.height
    except Exception:
        # Fallback to ffprobe if PIL fails
        try:
            cmd = ['ffprobe', '-v', 'quiet', '-print_format', 'json', '-show_streams', path]
            res = subprocess.check_output(cmd, timeout=5)
            data = json.loads(res)
            if 'streams' in data and len(data['streams']) > 0:
                info["width"] = data['streams'][0].get("width", 0)
                info["height"] = data['streams'][0].get("height", 0)
        except:
            pass
            
    return info

out = {}
base_dir = "/home/ga/Videos/stopmotion_output"

# Collect deliverables
out["master"] = get_media_info(os.path.join(base_dir, "commercial_master.mp4"))
out["cinematic"] = get_media_info(os.path.join(base_dir, "commercial_cinematic.mp4"))
out["web"] = get_media_info(os.path.join(base_dir, "commercial_web.mp4"))
out["preview"] = get_media_info(os.path.join(base_dir, "commercial_preview.mp4"))
out["proof_sheet"] = get_image_info(os.path.join(base_dir, "proof_sheet.png"))

# Read start time
try:
    with open("/tmp/task_start_time.txt", "r") as f:
        out["start_time"] = float(f.read().strip())
except:
    out["start_time"] = 0.0

# Write result file
with open("/tmp/task_result.json", "w") as f:
    json.dump(out, f, indent=2)
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true

# Copy the manifest so the verifier can read it too
MANIFEST_PATH="/home/ga/Videos/stopmotion_output/assembly_manifest.json"
if [ -f "$MANIFEST_PATH" ]; then
    cp "$MANIFEST_PATH" /tmp/assembly_manifest.json
    chmod 666 /tmp/assembly_manifest.json 2>/dev/null || true
fi

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export complete ==="