#!/bin/bash
set -e
echo "=== Setting up stream_playback_udp_json task ==="

# Source shared utilities
source /home/ga/openbci_task_utils.sh || {
    echo "WARNING: Could not source openbci_task_utils.sh"
}

# Record task start time
date +%s > /tmp/task_start_time.txt

# ============================================================
# 1. Ensure Recording File Exists
# ============================================================
REC_DIR="/home/ga/Documents/OpenBCI_GUI/Recordings"
REC_FILE="OpenBCI-EEG-S001-MotorImagery.txt"
FULL_PATH="$REC_DIR/$REC_FILE"

mkdir -p "$REC_DIR"

if [ ! -f "$FULL_PATH" ]; then
    echo "Copying recording file from data cache..."
    # Try multiple possible source locations
    if [ -f "/opt/openbci_data/$REC_FILE" ]; then
        cp "/opt/openbci_data/$REC_FILE" "$FULL_PATH"
    elif [ -f "/workspace/data/$REC_FILE" ]; then
        cp "/workspace/data/$REC_FILE" "$FULL_PATH"
    elif [ -f "/workspace/data/OpenBCI-EEG-S001-MotorImagery.txt" ]; then
         cp "/workspace/data/OpenBCI-EEG-S001-MotorImagery.txt" "$FULL_PATH"
    else
        echo "WARNING: Motor Imagery recording file not found!"
        # Fallback to eyes open if motor imagery is missing
        if [ -f "/opt/openbci_data/OpenBCI-EEG-S001-EyesOpen.txt" ]; then
            echo "Falling back to Eyes Open recording..."
            cp "/opt/openbci_data/OpenBCI-EEG-S001-EyesOpen.txt" "$FULL_PATH"
        fi
    fi
fi

chown ga:ga "$FULL_PATH"
echo "Recording file ready at: $FULL_PATH"

# ============================================================
# 2. Start Background UDP Listener
# ============================================================
echo "Starting background UDP listener on port 12345..."

# Kill any existing listener
pkill -f "udp_listener.py" || true

# Create the listener script
cat > /home/ga/udp_listener.py << 'PYEOF'
import socket
import json
import time
import sys
import os

UDP_IP = "127.0.0.1"
UDP_PORT = 12345
LOG_FILE = "/tmp/udp_stream_log.jsonl"

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
try:
    sock.bind((UDP_IP, UDP_PORT))
    print(f"Listening on {UDP_IP}:{UDP_PORT}")
except OSError as e:
    print(f"Error binding to port: {e}")
    sys.exit(1)

# Ensure log file is empty
with open(LOG_FILE, 'w') as f:
    pass

count = 0
start_time = time.time()

# Run for up to 10 minutes (task duration)
while time.time() - start_time < 600:
    try:
        sock.settimeout(1.0)
        data, addr = sock.recvfrom(65535) # Buffer size
        
        # Log the raw data + timestamp
        entry = {
            "timestamp": time.time(),
            "size": len(data),
            "raw_preview": str(data[:50]),
            "is_json": False,
            "content": None
        }

        try:
            # Try to parse as JSON
            json_str = data.decode('utf-8')
            json_data = json.loads(json_str)
            entry["is_json"] = True
            entry["content"] = json_data
        except:
            pass

        with open(LOG_FILE, 'a') as f:
            f.write(json.dumps(entry) + "\n")
        
        count += 1
        if count % 10 == 0:
            print(f"Received {count} packets")
            
    except socket.timeout:
        continue
    except Exception as e:
        print(f"Error: {e}")

sock.close()
PYEOF

chown ga:ga /home/ga/udp_listener.py

# Launch listener in background as ga user
su - ga -c "python3 /home/ga/udp_listener.py > /tmp/udp_listener.log 2>&1 &"

# ============================================================
# 3. Launch OpenBCI GUI
# ============================================================
# Launch fresh instance (kill old ones)
pkill -f "OpenBCI_GUI" || true
sleep 1

echo "Launching OpenBCI GUI..."
su - ga -c "bash /home/ga/launch_openbci.sh > /dev/null 2>&1 &"

# Wait for window
wait_for_openbci 45

# Maximize
wmctrl -r "OpenBCI_GUI" -b add,maximized_vert,maximized_horz 2>/dev/null || true
wmctrl -a "OpenBCI_GUI" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="