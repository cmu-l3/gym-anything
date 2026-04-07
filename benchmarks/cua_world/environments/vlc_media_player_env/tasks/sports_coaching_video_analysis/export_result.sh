#!/bin/bash
echo "=== Exporting task results ==="

# Record final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Run a python script inside the container to reliably analyze media files with ffprobe
# and assemble the results into a single JSON file for the verifier.
cat > /tmp/analyze_results.py << 'PYEOF'
import os
import json
import subprocess

def get_media_info(filepath):
    if not os.path.exists(filepath):
        return None
        
    stat = os.stat(filepath)
    info = {
        "exists": True,
        "size_bytes": stat.st_size,
        "mtime": stat.st_mtime
    }
    
    try:
        cmd = [
            'ffprobe', '-v', 'error', 
            '-show_entries', 'format=duration,bit_rate', 
            '-show_streams', '-of', 'json', filepath
        ]
        out = subprocess.check_output(cmd, stderr=subprocess.STDOUT).decode('utf-8')
        data = json.loads(out)
        
        if 'format' in data:
            if 'duration' in data['format']:
                info['duration'] = float(data['format']['duration'])
            if 'bit_rate' in data['format']:
                info['bitrate'] = int(data['format']['bit_rate'])
                
        for stream in data.get('streams', []):
            codec_type = stream.get('codec_type')
            if codec_type == 'video':
                info['video_codec'] = stream.get('codec_name')
                info['width'] = stream.get('width')
                info['height'] = stream.get('height')
            elif codec_type == 'audio':
                info['audio_codec'] = stream.get('codec_name')
                info['audio_channels'] = int(stream.get('channels', 0))
    except Exception as e:
        info['probe_error'] = str(e)
        
    return info

output_dir = "/home/ga/Videos/game_analysis"
results = {"files": {}}

# Get task start time
try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        results['task_start_time'] = float(f.read().strip())
except:
    results['task_start_time'] = 0.0

# 1. Check Play Clips
for i in range(1, 7):
    filename = f"play_0{i}.mp4"
    results["files"][filename] = get_media_info(os.path.join(output_dir, filename))

# 2. Check Slow-Mo Clips
for i in [2, 4, 6]:
    filename = f"slowmo_0{i}.mp4"
    results["files"][filename] = get_media_info(os.path.join(output_dir, filename))

# 3. Check Snapshots
for i in range(1, 7):
    filename = f"formation_0{i}.png"
    results["files"][filename] = get_media_info(os.path.join(output_dir, filename))

# 4. Check Commentary Audio
results["files"]["coach_commentary.mp3"] = get_media_info(os.path.join(output_dir, "coach_commentary.mp3"))

# 5. Check Playlist
playlist_path = os.path.join(output_dir, "highlights.m3u")
if os.path.exists(playlist_path):
    results["files"]["highlights.m3u"] = {"exists": True}
    try:
        with open(playlist_path, 'r') as f:
            lines = [l.strip() for l in f.readlines() if l.strip() and not l.startswith('#')]
            results["playlist_entries"] = lines
    except:
        results["playlist_entries"] = []
else:
    results["files"]["highlights.m3u"] = None
    results["playlist_entries"] = []

# 6. Check Manifest
manifest_path = os.path.join(output_dir, "game_manifest.json")
if os.path.exists(manifest_path):
    results["files"]["game_manifest.json"] = {"exists": True}
    try:
        with open(manifest_path, 'r') as f:
            results["manifest_content"] = json.load(f)
    except:
        results["manifest_content"] = "invalid_json"
else:
    results["files"]["game_manifest.json"] = None
    results["manifest_content"] = None

# Save result JSON for verifier
with open('/tmp/task_result.json', 'w') as f:
    json.dump(results, f, indent=2)
PYEOF

python3 /tmp/analyze_results.py

echo "Result JSON generated at /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export complete ==="