#!/bin/bash
set -e

echo "=== Setting up TCP Handshake Latency Task ==="

# 1. timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Verify Data Availability
PCAP_PATH="/home/ga/Documents/captures/200722_tcp_anon.pcapng"
if [ ! -f "$PCAP_PATH" ]; then
    echo "ERROR: PCAP file not found at $PCAP_PATH"
    # Try to recover by downloading if missing (using the logic from install script)
    wget -q -O "$PCAP_PATH" "https://wiki.wireshark.org/uploads/1894ec2950fd0e1bfbdac49b3de0bc92/200722_tcp_anon.pcapng" || true
fi

# 3. Clean previous run artifacts
rm -f /home/ga/Documents/captures/handshake_latencies.csv
rm -f /home/ga/Documents/captures/handshake_summary.txt
rm -f /tmp/task_result.json

# 4. Launch Wireshark
if ! pgrep -f "wireshark" > /dev/null; then
    echo "Starting Wireshark..."
    su - ga -c "DISPLAY=:1 wireshark '$PCAP_PATH' > /dev/null 2>&1 &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "Wireshark"; then
            break
        fi
        sleep 1
    done
fi

# 5. Optimize Window
DISPLAY=:1 wmctrl -r "Wireshark" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Wireshark" 2>/dev/null || true

# 6. Initial Screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="