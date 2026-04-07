#!/bin/bash
echo "=== Exporting Security Camera Daily Digest Result ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Run a python script to safely inspect all media files and generate a structured JSON
# This avoids bash quoting/parsing issues when handling ffprobe outputs.
cat > /tmp/export_helper.py << 'EOF'
import json
import os
import subprocess

def get_task_start():
    try:
        with open('/tmp/task_start_time.txt', 'r') as f:
            return float(f.read().strip())
    except Exception:
        return 0.0

def get_media_info(path, start_time):
    if not os.path.exists(path):
        return {"exists": False}
    
    mtime = os.path.getmtime(path)
    res = {
        "exists": True,
        "size": os.path.getsize(path),
        "mtime": mtime,
        "newly_created": mtime > start_time
    }
    
    try:
        cmd = [
            'ffprobe', '-v', 'error',
            '-show_entries', 'format=duration:stream=codec_type,codec_name',
            '-of', 'json', path
        ]
        out = subprocess.check_output(cmd, timeout=10).decode('utf-8')
        data = json.loads(out)
        
        res['duration'] = float(data.get('format', {}).get('duration', 0))
        streams = data.get('streams', [])
        
        res['has_video'] = any(s.get('codec_type') == 'video' for s in streams)
        res['has_audio'] = any(s.get('codec_type') == 'audio' for s in streams)
        
        v_stream = next((s for s in streams if s.get('codec_type') == 'video'), None)
        if v_stream:
            res['vcodec'] = v_stream.get('codec_name')
            
    except Exception as e:
        res['error'] = str(e)
        
    return res

def main():
    start_time = get_task_start()
    
    result = {
        "timelapses": {},
        "incidents": {},
        "frames": [],
        "manifest_exists": os.path.exists('/home/ga/Videos/daily_digest/digest_manifest.json')
    }
    
    # Check timelapses
    for cam in ['lobby', 'parking', 'loading']:
        path = f'/home/ga/Videos/daily_digest/timelapse_{cam}.mp4'
        result["timelapses"][cam] = get_media_info(path, start_time)
        
    # Check incidents
    for i in range(1, 5):
        path = f'/home/ga/Videos/daily_digest/incidents/incident_{i}.mp4'
        result["incidents"][f"incident_{i}"] = get_media_info(path, start_time)
        
    # Check frames
    frame_dir = '/home/ga/Videos/daily_digest/frames/'
    if os.path.exists(frame_dir):
        for f in os.listdir(frame_dir):
            if f.endswith('.png'):
                p = os.path.join(frame_dir, f)
                mtime = os.path.getmtime(p)
                result["frames"].append({
                    "name": f,
                    "size": os.path.getsize(p),
                    "newly_created": mtime > start_time
                })
                
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f, indent=2)

if __name__ == "__main__":
    main()
EOF

# Execute the helper script
python3 /tmp/export_helper.py

# Ensure correct permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Results written to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export complete ==="