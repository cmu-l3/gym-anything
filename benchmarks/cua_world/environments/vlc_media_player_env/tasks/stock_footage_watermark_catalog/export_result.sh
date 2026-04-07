#!/bin/bash
echo "=== Exporting stock_footage_watermark_catalog results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

mkdir -p /tmp/previews_output

# Copy files from target directory
if [ "$(ls -A /home/ga/Videos/previews 2>/dev/null)" ]; then
    cp -r /home/ga/Videos/previews/* /tmp/previews_output/ 2>/dev/null || true
fi

# Extract frames from preview videos to use for VLM watermark/timecode verification
echo "Extracting sample frames for verification..."
for f in /tmp/previews_output/preview_*.mp4; do
    if [ -f "$f" ]; then
        fname=$(basename "$f")
        # Extract frame at 7 seconds
        ffmpeg -y -ss 00:00:07 -i "$f" -vframes 1 -q:v 2 "/tmp/previews_output/frame_${fname}.jpg" 2>/dev/null || true
    fi
done

echo "Dumping media metadata..."
# Create python script to safely dump media properties using ffprobe
cat > /tmp/dump_info.py << 'EOF'
import json, os, subprocess
result = {}
d = '/tmp/previews_output'
if os.path.exists(d):
    for f in os.listdir(d):
        p = os.path.join(d, f)
        if f.endswith('.mp4'):
            cmd = ['ffprobe', '-v', 'error', '-show_entries', 'format=duration:stream=codec_name,width,height', '-of', 'json', p]
            res = subprocess.run(cmd, capture_output=True, text=True)
            if res.returncode == 0:
                result[f] = json.loads(res.stdout)
        elif f.endswith('.png'):
            cmd = ['ffprobe', '-v', 'error', '-show_entries', 'stream=width,height', '-of', 'json', p]
            res = subprocess.run(cmd, capture_output=True, text=True)
            if res.returncode == 0:
                result[f] = json.loads(res.stdout)
with open('/tmp/previews_output/media_info.json', 'w') as out:
    json.dump(result, out)
EOF
python3 /tmp/dump_info.py 2>/dev/null || true

# Dump file statistics (mtime, size) for anti-gaming checks
cat > /tmp/dump_stats.py << 'EOF'
import json, os
result = {}
d = '/tmp/previews_output'
if os.path.exists(d):
    for f in os.listdir(d):
        p = os.path.join(d, f)
        if os.path.isfile(p):
            result[f] = {'size': os.path.getsize(p), 'mtime': os.path.getmtime(p)}
try:
    with open('/tmp/task_start_time.txt', 'r') as start:
        result['task_start_time'] = float(start.read().strip())
except:
    result['task_start_time'] = 0
with open('/tmp/previews_output/file_stats.json', 'w') as out:
    json.dump(result, out)
EOF
python3 /tmp/dump_stats.py 2>/dev/null || true

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true
cp /tmp/task_final.png /tmp/previews_output/ 2>/dev/null || true

# Archive all results for easy copy_from_env
cd /tmp
tar -czf /tmp/task_result.tar.gz previews_output
chmod 666 /tmp/task_result.tar.gz

# Cleanup
pkill -u ga -f vlc || true
echo "=== Export complete ==="