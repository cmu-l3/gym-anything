#!/bin/bash
echo "=== Exporting task results ==="

TASK_END=$(date +%s)
TASK_START=$(cat C:/temp/task_start_time.txt 2>/dev/null || cat /c/temp/task_start_time.txt 2>/dev/null || echo "0")

# Python script to safely check files and export JSON in Windows
cat << EOF > C:/temp/export_result.py
import os
import json
import subprocess

task_start = int("$TASK_START")
task_end = int("$TASK_END")
output_path = r"C:\Users\Docker\Documents\converted_3d_points.csv"

output_exists = os.path.exists(output_path)
file_created_during_task = False
output_size = 0

if output_exists:
    output_size = os.path.getsize(output_path)
    ctime = os.path.getctime(output_path)
    mtime = os.path.getmtime(output_path)
    # Give 5 seconds buffer for filesystem delays
    if ctime >= task_start - 5 or mtime >= task_start - 5:
        file_created_during_task = True

app_running = False
try:
    tasklist_out = subprocess.check_output('tasklist', shell=True).decode()
    if 'TopoCal.exe' in tasklist_out:
        app_running = True
except:
    pass

try:
    from PIL import ImageGrab
    im = ImageGrab.grab()
    im.save(r'C:\temp\task_final.png')
except:
    pass

result = {
    "task_start": task_start,
    "task_end": task_end,
    "output_exists": output_exists,
    "file_created_during_task": file_created_during_task,
    "output_size_bytes": output_size,
    "app_was_running": app_running,
    "screenshot_path": r"C:\temp\task_final.png"
}

with open(r"C:\temp\task_result.json", "w") as f:
    json.dump(result, f, indent=4)
EOF

python C:/temp/export_result.py || python.exe C:/temp/export_result.py

cat C:/temp/task_result.json 2>/dev/null || cat /c/temp/task_result.json
echo ""
echo "=== Export complete ==="