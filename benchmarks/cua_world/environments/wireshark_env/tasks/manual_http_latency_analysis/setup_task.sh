#!/bin/bash
set -e
echo "=== Setting up Manual HTTP Latency Analysis Task ==="

# 1. timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Verify Data Existence
PCAP_PATH="/home/ga/Documents/captures/http.cap"
if [ ! -f "$PCAP_PATH" ]; then
    echo "ERROR: http.cap not found at $PCAP_PATH"
    # Fallback: try to find it in default locations or download
    if [ -f "/usr/share/doc/wireshark-common/examples/http.cap" ]; then
        cp /usr/share/doc/wireshark-common/examples/http.cap "$PCAP_PATH"
    else
        echo "Attempting download..."
        wget -q -O "$PCAP_PATH" "https://wiki.wireshark.org/uploads/27707187aeb30df68e70c8fb9d614981/http.cap" || true
    fi
fi
chmod 644 "$PCAP_PATH"

# 3. Clean previous artifacts
rm -f /home/ga/Documents/captures/latency_report.json
rm -f /home/ga/Documents/captures/latency_evidence.png

# 4. Start Wireshark with the file loaded
# This ensures the agent starts in the correct context
if ! pgrep -f "wireshark" > /dev/null; then
    echo "Starting Wireshark..."
    su - ga -c "DISPLAY=:1 wireshark '$PCAP_PATH' &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "Wireshark"; then
            echo "Wireshark window detected"
            break
        fi
        sleep 1
    done
    sleep 2
fi

# 5. Maximize window
DISPLAY=:1 wmctrl -r "Wireshark" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Wireshark" 2>/dev/null || true

# 6. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="