#!/bin/bash
echo "=== Exporting create_list_organize_data results ==="

cat << 'EOF' > C:/temp/export_result.py
import os
import time
import json
import socket

result = {
    "task_end_time": int(time.time()),
    "gpx_exists": False,
    "gpx_size_bytes": 0,
    "gpx_mtime": 0,
    "start_time": 0
}

# 1. Read start time
try:
    with open(r"C:\temp\task_start_time.txt", "r") as f:
        result["start_time"] = int(f.read().strip())
except:
    pass

# 2. Check output file
out_file = r"C:\workspace\output\fall_survey_2024.gpx"
if os.path.exists(out_file):
    result["gpx_exists"] = True
    result["gpx_size_bytes"] = os.path.getsize(out_file)
    result["gpx_mtime"] = int(os.path.getmtime(out_file))

# 3. Take final screenshot via GUI server
def send_gui_cmd(cmd):
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.connect(('127.0.0.1', 5555))
        s.sendall(json.dumps(cmd).encode('utf-8'))
        s.recv(4096)
        s.close()
    except:
        pass

send_gui_cmd({"action": "screenshot", "path": "C:\\temp\\task_final.png"})
result["screenshot_captured"] = os.path.exists(r"C:\temp\task_final.png")

# 4. Save result payload
with open(r"C:\temp\task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Export data generated:")
print(json.dumps(result, indent=2))
EOF

python C:/temp/export_result.py

echo "=== Export Complete ==="