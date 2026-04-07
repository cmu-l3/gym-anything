#!/bin/bash
echo "=== Setting up wildfire_preattack_plan task ==="

# Create necessary workspace directories
mkdir -p /workspace/output
mkdir -p /workspace/evidence

# Clean previous artifacts if any
rm -f /workspace/output/fells_preattack_2024.gpx
rm -f /workspace/output/task_result.json

# Record task start time (anti-gaming: ensures exported file is new)
date +%s > /workspace/task_start_time.txt

# Launch BaseCamp with fells_loop data restored via the shared launch script.
# This calls Close-Browsers, Close-BaseCamp, Restore-BaseCampData,
# Launch-BaseCampInteractive, and Close-Browsers — matching the plan task pattern.
powershell.exe -ExecutionPolicy Bypass -File "C:\workspace\scripts\launch_app_pretask.ps1"

# Dismiss any remaining startup dialogs or popups via PyAutoGUI server
python3 -c "
import socket, json, time

def send_cmd(cmd):
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(2.0)
        s.connect(('127.0.0.1', 5555))
        s.sendall(json.dumps(cmd).encode('utf-8'))
        resp = s.recv(4096)
        s.close()
        return json.loads(resp)
    except Exception as e:
        print(f'Error sending cmd: {e}')
        return None

# Press escape a few times to dismiss any leftover dialogs
for _ in range(3):
    send_cmd({'action': 'press', 'key': 'escape'})
    time.sleep(0.5)

# Take initial screenshot to document starting state
send_cmd({'action': 'screenshot', 'path': 'C:\\\\workspace\\\\evidence\\\\task_initial_state.png'})
"

echo "=== wildfire_preattack_plan task setup complete ==="
