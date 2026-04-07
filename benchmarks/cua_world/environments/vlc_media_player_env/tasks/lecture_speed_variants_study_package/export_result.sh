#!/bin/bash
echo "=== Exporting lecture_speed_variants_study_package results ==="

# Take final state screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Prepare export payload directory
mkdir -p /tmp/export_payload
if [ -d /home/ga/Videos/study_package ]; then
    cp -r /home/ga/Videos/study_package/* /tmp/export_payload/ 2>/dev/null || true
fi

# Run ffprobe on all media files inside the container to ensure reliable metadata extraction
# This handles the case where the evaluating host environment might not have ffprobe installed
cat > /tmp/probe_files.py << 'EOF'
import os
import json
import subprocess

data = {}
base_dir = '/tmp/export_payload'

for root, dirs, files in os.walk(base_dir):
    for f in files:
        p = os.path.join(root, f)
        rel_path = os.path.relpath(p, base_dir)
        rel_path = rel_path.replace("\\", "/")  # Normalize for JSON keys
        
        try:
            stat = os.stat(p)
            entry = {'size': stat.st_size, 'mtime': stat.st_mtime}
            
            if f.lower().endswith(('.mp4', '.mp3', '.wav', '.mkv', '.avi')):
                try:
                    res = subprocess.run(
                        ['ffprobe', '-v', 'error', '-show_format', '-show_streams', '-of', 'json', p], 
                        capture_output=True, text=True
                    )
                    entry['ffprobe'] = json.loads(res.stdout)
                except Exception as e:
                    entry['ffprobe_error'] = str(e)
            
            data[rel_path] = entry
        except Exception:
            pass

with open('/tmp/export_metadata.json', 'w') as f:
    json.dump(data, f)
EOF

python3 /tmp/probe_files.py

# Clean up VLC
pkill -f vlc || true

echo "=== Export complete ==="