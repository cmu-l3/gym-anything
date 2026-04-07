#!/bin/bash
echo "=== Setting up SAR Search Grid task ==="

# Create necessary workspace directories
mkdir -p /workspace/output
mkdir -p /workspace/evidence

# Clean previous artifacts if any
rm -f /workspace/output/sar_grid.gpx
rm -f /workspace/output/task_result.json

# Record task start time (anti-gaming)
date +%s > /workspace/task_start_time.txt

# Ensure BaseCamp is running and in a clean state via PyAutoGUI server
# We assume the VM/container is already running BaseCamp, but we will dismiss any popups
# and maximize the window for the agent.
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

# Press escape a few times to dismiss any startup or error dialogs
for _ in range(3):
    send_cmd({'action': 'press', 'key': 'escape'})
    time.sleep(0.5)

# Take initial screenshot to document starting state
send_cmd({'action': 'screenshot', 'path': 'C:\\\\workspace\\\\evidence\\\\task_initial_state.png'})
"

echo "=== Task setup complete ==="