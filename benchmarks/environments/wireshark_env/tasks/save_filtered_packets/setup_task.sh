#!/bin/bash
set -e
echo "=== Setting up save_filtered_packets task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

PCAP_FILE="/home/ga/Documents/captures/200722_tcp_anon.pcapng"
OUTPUT_FILE="/home/ga/Documents/captures/syn_packets.pcapng"

# Verify source PCAP exists
if [ ! -s "$PCAP_FILE" ]; then
    echo "ERROR: Source PCAP file not found: $PCAP_FILE"
    # Try to redownload if missing (redundancy)
    wget -q -O "$PCAP_FILE" "https://wiki.wireshark.org/uploads/1894ec2950fd0e1bfbdac49b3de0bc92/200722_tcp_anon.pcapng" || true
fi

# Remove any pre-existing output file (clean state)
rm -f "$OUTPUT_FILE" 2>/dev/null || true
rm -f /home/ga/Documents/captures/syn_packets.pcap 2>/dev/null || true
rm -f /home/ga/Documents/captures/syn_packets.cap 2>/dev/null || true

# Compute ground truth: count SYN-only packets in the original
# Filter: SYN=1 AND ACK=0
EXPECTED_SYN_COUNT=$(tshark -r "$PCAP_FILE" -Y "tcp.flags.syn == 1 && tcp.flags.ack == 0" 2>/dev/null | wc -l)
TOTAL_PACKET_COUNT=$(tshark -r "$PCAP_FILE" 2>/dev/null | wc -l)

echo "$EXPECTED_SYN_COUNT" > /tmp/expected_syn_count.txt
echo "$TOTAL_PACKET_COUNT" > /tmp/total_packet_count.txt

echo "Ground truth: $EXPECTED_SYN_COUNT SYN-only packets out of $TOTAL_PACKET_COUNT total"

# Kill any existing Wireshark instances
pkill -f wireshark 2>/dev/null || true
sleep 1

# Start Wireshark with the capture file loaded
echo "Starting Wireshark..."
su - ga -c "DISPLAY=:1 wireshark '$PCAP_FILE' > /dev/null 2>&1 &"
sleep 5

# Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Wireshark"; then
        echo "Wireshark window detected"
        break
    fi
    sleep 1
done

# Maximize and focus Wireshark
DISPLAY=:1 wmctrl -r "Wireshark" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Wireshark" 2>/dev/null || true

# Dismiss any startup dialogs if they appear
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take screenshot of initial state
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="