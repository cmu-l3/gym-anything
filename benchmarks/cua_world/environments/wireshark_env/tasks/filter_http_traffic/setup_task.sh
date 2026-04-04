#!/bin/bash
set -e

echo "=== Setting up filter_http_traffic task ==="

# Clean up any leftover temp files from previous tasks
rm -f /tmp/initial_* /tmp/ground_truth_* /tmp/task_result.json /tmp/task_end.png 2>/dev/null || true

# Record initial state: count HTTP packets in original capture using tshark
PCAP_FILE="/home/ga/Documents/captures/http.cap"

if [ ! -s "$PCAP_FILE" ]; then
    echo "ERROR: PCAP file not found or empty at $PCAP_FILE"
    exit 1
fi

# Count total packets and HTTP packets for baseline
TOTAL_PACKETS=$(tshark -r "$PCAP_FILE" 2>/dev/null | wc -l)
HTTP_PACKETS=$(tshark -r "$PCAP_FILE" -Y "http" 2>/dev/null | wc -l)

echo "$TOTAL_PACKETS" > /tmp/initial_total_packets
echo "$HTTP_PACKETS" > /tmp/initial_http_packets

echo "Initial state: $TOTAL_PACKETS total packets, $HTTP_PACKETS HTTP packets"

# Remove any previous filtered output
rm -f /home/ga/Documents/captures/filtered_http.pcap 2>/dev/null || true

# Open Wireshark with the HTTP capture file
echo "Opening Wireshark with http.cap..."
su - ga -c "DISPLAY=:1 wireshark /home/ga/Documents/captures/http.cap > /tmp/wireshark_task.log 2>&1 &"

# Wait for Wireshark to start
sleep 5

echo "=== Task setup complete ==="
