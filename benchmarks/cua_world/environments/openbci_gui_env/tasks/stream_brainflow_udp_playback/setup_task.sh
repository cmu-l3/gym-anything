#!/bin/bash
set -e
echo "=== Setting up stream_brainflow_udp_playback task ==="

# Source utilities
source /home/ga/openbci_task_utils.sh 2>/dev/null || source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt

# ============================================================
# 1. Ensure EEG Recording Exists
# ============================================================
RECORDINGS_DIR="/home/ga/Documents/OpenBCI_GUI/Recordings"
mkdir -p "$RECORDINGS_DIR"

TARGET_FILE="${RECORDINGS_DIR}/OpenBCI-EEG-S001-EyesOpen.txt"

# Copy from pre-loaded location if missing
if [ ! -f "$TARGET_FILE" ]; then
    if [ -f "/opt/openbci_data/OpenBCI-EEG-S001-EyesOpen.txt" ]; then
        cp "/opt/openbci_data/OpenBCI-EEG-S001-EyesOpen.txt" "$TARGET_FILE"
    elif [ -f "/workspace/data/OpenBCI-EEG-S001-EyesOpen.txt" ]; then
        cp "/workspace/data/OpenBCI-EEG-S001-EyesOpen.txt" "$TARGET_FILE"
    else
        echo "WARNING: EEG source file not found. Creating dummy file for structure check."
        # Create a valid-looking header so GUI doesn't crash immediately
        echo "%OpenBCI Raw EEG Data" > "$TARGET_FILE"
        echo "%Sample Rate = 250 Hz" >> "$TARGET_FILE"
        echo "%First Column = SampleIndex" >> "$TARGET_FILE"
        # Add some dummy data lines
        for i in {1..500}; do
            echo "$i, 10, 20, 30, 40, 50, 60, 70, 80" >> "$TARGET_FILE"
        done
    fi
fi
chown ga:ga "$TARGET_FILE"
echo "EEG file ready at: $TARGET_FILE"

# ============================================================
# 2. Start Background UDP Listener
# ============================================================
# This script listens on 127.0.0.1:9000 and records packet stats
cat > /tmp/udp_listener.py << 'EOF'
import socket
import sys
import time
import json
import signal

UDP_IP = "127.0.0.1"
UDP_PORT = 9000
OUTPUT_FILE = "/tmp/udp_listener_stats.json"

stats = {
    "packet_count": 0,
    "total_bytes": 0,
    "is_json": False,
    "is_binary": False,
    "first_packet_hex": "",
    "first_packet_ascii": ""
}

def save_stats():
    with open(OUTPUT_FILE, 'w') as f:
        json.dump(stats, f)

def handler(signum, frame):
    save_stats()
    sys.exit(0)

signal.signal(signal.SIGTERM, handler)
signal.signal(signal.SIGINT, handler)

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
try:
    sock.bind((UDP_IP, UDP_PORT))
    print(f"Listening on {UDP_IP}:{UDP_PORT}")
except Exception as e:
    print(f"Error binding: {e}")
    sys.exit(1)

sock.settimeout(1.0)

print("Starting loop...")
save_stats() # Init file

while True:
    try:
        data, addr = sock.recvfrom(4096)
        stats["packet_count"] += 1
        stats["total_bytes"] += len(data)
        
        # Analyze format on first packet
        if stats["packet_count"] == 1:
            stats["first_packet_hex"] = data.hex()[:50]
            try:
                decoded = data.decode('utf-8')
                stats["first_packet_ascii"] = decoded[:50]
                if decoded.strip().startswith('{') or "channel" in decoded:
                    stats["is_json"] = True
                else:
                    stats["is_binary"] = True # Likely binary if not clear JSON
            except:
                stats["is_binary"] = True
                stats["first_packet_ascii"] = "<non-ascii>"
        
        if stats["packet_count"] % 10 == 0:
            save_stats()
            
    except socket.timeout:
        continue
    except Exception as e:
        print(f"Error: {e}")
        break

save_stats()
EOF

# Kill any existing listener
pkill -f "udp_listener.py" || true

# Start listener as ga user
su - ga -c "python3 /tmp/udp_listener.py > /tmp/udp_listener.log 2>&1 &"
echo "UDP listener started on port 9000"

# ============================================================
# 3. Launch OpenBCI GUI
# ============================================================
echo "Launching OpenBCI GUI..."
launch_openbci # Uses utility function from openbci_task_utils.sh

# Wait for window
wait_for_openbci 60

# Maximize
DISPLAY=:1 wmctrl -r "OpenBCI_GUI" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="