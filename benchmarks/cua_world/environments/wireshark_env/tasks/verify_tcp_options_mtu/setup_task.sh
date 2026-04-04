#!/bin/bash
set -e
echo "=== Setting up verify_tcp_options_mtu task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

PCAP_PATH="/home/ga/Documents/captures/200722_tcp_anon.pcapng"

# Ensure the PCAP file exists (should be pre-downloaded by env)
if [ ! -f "$PCAP_PATH" ]; then
    echo "ERROR: Capture file not found at $PCAP_PATH"
    # Try to re-download if missing (fallback)
    wget -q -O "$PCAP_PATH" "https://wiki.wireshark.org/uploads/1894ec2950fd0e1bfbdac49b3de0bc92/200722_tcp_anon.pcapng" || true
fi

# Remove any previous report file to ensure clean state
rm -f /home/ga/Documents/captures/tcp_options_report.txt

# Start Wireshark with the file loaded
if ! pgrep -f "wireshark" > /dev/null; then
    echo "Starting Wireshark..."
    su - ga -c "DISPLAY=:1 wireshark '$PCAP_PATH' > /dev/null 2>&1 &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "wireshark" > /dev/null; then
            break
        fi
        sleep 1
    done
fi

# Maximize Wireshark
DISPLAY=:1 wmctrl -r "Wireshark" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "Wireshark" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="