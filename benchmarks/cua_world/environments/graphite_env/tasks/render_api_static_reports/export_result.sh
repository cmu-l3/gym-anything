#!/bin/bash
echo "=== Exporting render_api_static_reports result ==="

# Record task end time and take final screenshot
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# We will use Python to safely gather all file metadata and script contents
python3 << EOF
import os
import json
import subprocess

result = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "dir_exists": os.path.isdir("/home/ga/reports"),
    "script_exists": False,
    "script_executable": False,
    "script_content": "",
    "files": {}
}

script_path = "/home/ga/reports/generate_reports.sh"
if os.path.isfile(script_path):
    result["script_exists"] = True
    result["script_executable"] = os.access(script_path, os.X_OK)
    try:
        with open(script_path, "r", encoding="utf-8") as f:
            result["script_content"] = f.read()
    except Exception as e:
        result["script_content"] = f"ERROR READING: {e}"

expected_files = [
    "fleet_cpu_overview.png", 
    "disk_write_rate.png", 
    "temperature_analysis.png"
]

for fname in expected_files:
    path = os.path.join("/home/ga/reports", fname)
    f_info = {
        "exists": False, 
        "size": 0, 
        "mtime": 0,
        "width": 0, 
        "height": 0, 
        "format": "none"
    }
    if os.path.isfile(path):
        f_info["exists"] = True
        f_info["size"] = os.path.getsize(path)
        f_info["mtime"] = os.path.getmtime(path)
        
        # Use ImageMagick 'identify' to get image dimensions and format securely
        try:
            out = subprocess.check_output(
                ["identify", "-format", "%w %h %m", path], 
                stderr=subprocess.STDOUT
            ).decode("utf-8").strip()
            parts = out.split()
            if len(parts) >= 3:
                f_info["width"] = int(parts[0])
                f_info["height"] = int(parts[1])
                f_info["format"] = parts[2]
        except Exception:
            pass
            
    result["files"][fname] = f_info

# Write to tmp file, then move to final destination
with open("/tmp/render_api_result_tmp.json", "w") as f:
    json.dump(result, f, indent=2)
EOF

mv /tmp/render_api_result_tmp.json /tmp/render_api_result.json
chmod 644 /tmp/render_api_result.json

echo "Result saved to /tmp/render_api_result.json"
cat /tmp/render_api_result.json
echo "=== Export complete ==="