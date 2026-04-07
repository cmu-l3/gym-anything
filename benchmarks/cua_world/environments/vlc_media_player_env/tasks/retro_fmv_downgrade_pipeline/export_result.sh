#!/bin/bash
echo "=== Exporting Retro FMV Downgrade task results ==="

# Record final state screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# We will use Python to safely parse ffprobe on the generated files and export a clean JSON
# This avoids massive file transfers of AVIs through the copy_from_env mechanism
cat > /tmp/export_probes.py << 'PYEOF'
import os
import json
import subprocess

results = {}
output_dir = "/home/ga/Videos/retro_assets/"
task_start = 0

try:
    with open("/tmp/task_start_time.txt", "r") as f:
        task_start = int(f.read().strip())
except Exception:
    pass

for i in range(1, 4):
    scene_id = f"scene{i}"
    file_path = os.path.join(output_dir, f"scene{i}_fmv.avi")
    
    file_info = {
        "exists": False,
        "mtime": 0,
        "created_during_task": False,
        "ffprobe": None,
        "file_size_kb": 0
    }
    
    if os.path.exists(file_path):
        file_info["exists"] = True
        mtime = os.path.getmtime(file_path)
        file_info["mtime"] = mtime
        file_info["created_during_task"] = mtime > task_start
        file_info["file_size_kb"] = os.path.getsize(file_path) // 1024
        
        # Run ffprobe
        cmd = [
            "ffprobe", "-v", "error", 
            "-show_format", "-show_streams", 
            "-of", "json", file_path
        ]
        try:
            res = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
            if res.returncode == 0:
                file_info["ffprobe"] = json.loads(res.stdout)
        except Exception as e:
            file_info["error"] = str(e)
            
    results[scene_id] = file_info

with open("/tmp/retro_probe_results.json", "w") as f:
    json.dump(results, f, indent=2)
PYEOF

python3 /tmp/export_probes.py

# Extract middle frames from the AVIs to verify grayscale and hardsubbing
for i in {1..3}; do
    TARGET="/home/ga/Videos/retro_assets/scene${i}_fmv.avi"
    FRAME_OUT="/tmp/scene${i}_frame.png"
    if [ -f "$TARGET" ]; then
        # Extract frame at 00:00:09 (to catch the second subtitle line)
        ffmpeg -y -i "$TARGET" -ss 00:00:09 -vframes 1 "$FRAME_OUT" 2>/dev/null
    fi
done

# Copy agent's JSON report
if [ -f "/home/ga/Videos/retro_assets/compression_report.json" ]; then
    cp "/home/ga/Videos/retro_assets/compression_report.json" "/tmp/agent_compression_report.json"
fi

echo "Results exported to /tmp for verifier access."
echo "=== Export complete ==="