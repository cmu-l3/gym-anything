#!/bin/bash
set -euo pipefail

echo "=== Setting up create_display_filter_macro task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure the required PCAP file exists
PCAP_FILE="/home/ga/Documents/captures/200722_tcp_anon.pcapng"
if [ ! -f "$PCAP_FILE" ]; then
    echo "ERROR: PCAP file not found at $PCAP_FILE"
    # Try to download if missing (backup)
    wget -q -O "$PCAP_FILE" "https://wiki.wireshark.org/uploads/1894ec2950fd0e1bfbdac49b3de0bc92/200722_tcp_anon.pcapng" || true
fi

# Clean up previous task artifacts
rm -f /home/ga/Documents/packet_count.txt
rm -f /tmp/task_result.json

# Reset Display Filter Macros to default/empty
# Wireshark stores macros in ~/.config/wireshark/dfilter_macros
MACRO_FILE="/home/ga/.config/wireshark/dfilter_macros"
if [ -f "$MACRO_FILE" ]; then
    echo "Clearing existing macros..."
    rm "$MACRO_FILE"
fi

# Ensure Wireshark config directory exists
mkdir -p /home/ga/.config/wireshark
chown -R ga:ga /home/ga/.config/wireshark

# Start Wireshark maximized
echo "Starting Wireshark..."
if ! pgrep -f "wireshark" > /dev/null; then
    su - ga -c "DISPLAY=:1 wireshark &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "Wireshark"; then
            echo "Wireshark window detected"
            break
        fi
        sleep 1
    done
fi

# Maximize the window
DISPLAY=:1 wmctrl -r "Wireshark" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Wireshark" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="