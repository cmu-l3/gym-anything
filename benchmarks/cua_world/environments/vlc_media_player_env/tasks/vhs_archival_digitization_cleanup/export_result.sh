#!/bin/bash
# Export results for vhs_archival_digitization_cleanup task
set -e

echo "=== Exporting vhs_archival_digitization_cleanup results ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Python script to analyze output files and export to JSON
cat > /tmp/analyze_outputs.py << 'PYEOF'
import os
import json
import subprocess

result = {
    "files": {},
    "task_start": 0,
    "screenshot_path": "/tmp/task_final.png"
}

try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        result["task_start"] = int(f.read().strip())
except Exception:
    pass

expected_files = [
    "access_tape_1992_grad.mp4",
    "access_tape_1994_picnic.mp4",
    "access_tape_1995_storm.mp4"
]

out_dir = "/home/ga/Videos/archive_access"

for fname in expected_files:
    path = os.path.join(out_dir, fname)
    if os.path.exists(path):
        mtime = os.path.getmtime(path)
        size = os.path.getsize(path)
        
        # Run ffprobe to get comprehensive stream info
        cmd = ['ffprobe', '-v', 'error', '-show_format', '-show_streams', '-of', 'json', path]
        try:
            res = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
            data = json.loads(res.stdout)
            
            v_stream = next((s for s in data.get('streams', []) if s.get('codec_type') == 'video'), {})
            a_stream = next((s for s in data.get('streams', []) if s.get('codec_type') == 'audio'), {})
            fmt = data.get('format', {})
            
            result["files"][fname] = {
                "exists": True,
                "mtime": mtime,
                "size": size,
                "duration": float(fmt.get('duration', 0)),
                "v_codec": v_stream.get('codec_name', '').lower(),
                "width": v_stream.get('width', 0),
                "height": v_stream.get('height', 0),
                "a_codec": a_stream.get('codec_name', '').lower(),
                "channels": a_stream.get('channels', 0),
                "tags": {k.lower(): str(v) for k, v in fmt.get('tags', {}).items()}
            }
        except Exception as e:
            result["files"][fname] = {"exists": True, "error": str(e), "mtime": mtime}
    else:
        result["files"][fname] = {"exists": False}

with open('/tmp/vhs_task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

python3 /tmp/analyze_outputs.py

chmod 666 /tmp/vhs_task_result.json 2>/dev/null || true

echo "Export complete. Result JSON generated at /tmp/vhs_task_result.json"
cat /tmp/vhs_task_result.json