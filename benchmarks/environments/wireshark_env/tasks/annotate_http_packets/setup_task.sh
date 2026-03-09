#!/bin/bash
set -e
echo "=== Setting up annotate_http_packets task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Define file paths
INPUT_PCAP="/home/ga/Documents/captures/http.cap"
OUTPUT_PCAP="/home/ga/Documents/captures/http_annotated.pcapng"

# Remove any previous output to ensure clean state
rm -f "$OUTPUT_PCAP"

# Verify source file exists
if [ ! -f "$INPUT_PCAP" ]; then
    echo "ERROR: Input file $INPUT_PCAP not found!"
    exit 1
fi

# Record original packet count for verification
ORIG_COUNT=$(tshark -r "$INPUT_PCAP" 2>/dev/null | wc -l)
echo "$ORIG_COUNT" > /tmp/original_packet_count.txt
echo "Original packet count: $ORIG_COUNT"

# Kill any existing Wireshark instances
pkill -f wireshark 2>/dev/null || true
sleep 1

# Launch Wireshark with the http.cap file
echo "Launching Wireshark with http.cap..."
su - ga -c "DISPLAY=:1 wireshark '$INPUT_PCAP' > /dev/null 2>&1 &"
sleep 5

# Wait for Wireshark window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "wireshark"; then
        echo "Wireshark window detected"
        break
    fi
    sleep 1
done

# Focus and maximize Wireshark window
# This is critical for VLM visibility and agent interaction
DISPLAY=:1 wmctrl -a "Wireshark" 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -r "Wireshark" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Dismiss any startup dialogs (like "Software Update" or first-run warnings)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take screenshot of initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="