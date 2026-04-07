#!/bin/bash
echo "=== Setting up create_list_organize_data task ==="

# Create a robust Python setup script to handle Windows paths and the PyAutoGUI server
cat << 'EOF' > C:/temp/setup_task.py
import os
import time
import shutil
import subprocess
import json
import socket

# 1. Ensure temp and output directories exist
os.makedirs(r"C:\temp", exist_ok=True)
os.makedirs(r"C:\workspace\output", exist_ok=True)

# 2. Record task start time
start_time = int(time.time())
with open(r"C:\temp\task_start_time.txt", "w") as f:
    f.write(str(start_time))

# 3. Clean up any previous output
out_file = r"C:\workspace\output\fall_survey_2024.gpx"
if os.path.exists(out_file):
    try:
        os.remove(out_file)
    except Exception as e:
        print(f"Warning: Could not remove old output file: {e}")

# 4. Restore BaseCamp database to ensure clean state with fells_loop data
db_base = os.path.expandvars(r"%APPDATA%\Garmin\BaseCamp\Database")
backup_dir = r"C:\GarminTools\BaseCampBackup\Database"
version_file = r"C:\GarminTools\BaseCampBackup\version.txt"

# Kill BaseCamp if running
subprocess.run(["taskkill", "/F", "/IM", "BaseCamp.exe"], capture_output=True)
time.sleep(2)

if os.path.exists(backup_dir) and os.path.exists(version_file):
    try:
        with open(version_file, "r") as f:
            version = f.read().strip()
        
        target_dir = os.path.join(db_base, version)
        if os.path.exists(target_dir):
            shutil.rmtree(target_dir)
            
        shutil.copytree(backup_dir, target_dir)
        print(f"Restored BaseCamp database from backup (Version {version})")
    except Exception as e:
        print(f"Warning: Database restore failed: {e}")

# 5. Launch BaseCamp
bc_exe = r"C:\Program Files (x86)\Garmin\BaseCamp\BaseCamp.exe"
if not os.path.exists(bc_exe):
    bc_exe = r"C:\Program Files\Garmin\BaseCamp\BaseCamp.exe"

if os.path.exists(bc_exe):
    subprocess.Popen([bc_exe])
    print("Launched Garmin BaseCamp")
else:
    print("ERROR: BaseCamp executable not found.")

# 6. Wait for UI and dismiss dialogs via PyAutoGUI server
print("Waiting for BaseCamp to load...")
time.sleep(15)

def send_gui_cmd(cmd):
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.connect(('127.0.0.1', 5555))
        s.sendall(json.dumps(cmd).encode('utf-8'))
        resp = s.recv(4096)
        s.close()
        return json.loads(resp)
    except Exception as e:
        print(f"GUI server error: {e}")
        return None

# Hit escape a few times to dismiss "No devices connected" or update dialogs
for _ in range(3):
    send_gui_cmd({"action": "press", "key": "escape"})
    time.sleep(0.5)
send_gui_cmd({"action": "press", "key": "enter"})
time.sleep(1)

# Take initial screenshot to prove starting state
send_gui_cmd({"action": "screenshot", "path": "C:\\temp\\task_initial.png"})
print("Initial screenshot captured.")

EOF

# Execute the setup script
python C:/temp/setup_task.py

echo "=== Setup Complete ==="