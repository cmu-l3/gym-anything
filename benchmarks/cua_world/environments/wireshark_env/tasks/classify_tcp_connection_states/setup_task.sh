#!/bin/bash
set -euo pipefail

echo "=== Setting up classify_tcp_connection_states task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target PCAP file
PCAP_FILE="/home/ga/Documents/captures/200722_tcp_anon.pcapng"

if [ ! -s "$PCAP_FILE" ]; then
    echo "ERROR: Required capture file $PCAP_FILE is missing or empty!"
    # Try to re-download if missing (fallback)
    wget -q -O "$PCAP_FILE" "https://wiki.wireshark.org/uploads/1894ec2950fd0e1bfbdac49b3de0bc92/200722_tcp_anon.pcapng" || true
    chmod 644 "$PCAP_FILE"
fi

if [ ! -s "$PCAP_FILE" ]; then
    echo "FATAL: Could not ensure PCAP file existence."
    exit 1
fi

# Clean previous artifacts
rm -f /home/ga/Documents/captures/tcp_connection_state_report.txt
rm -f /tmp/ground_truth.json

echo "Computing ground truth (this may take a moment)..."

# 1. Total TCP Streams
TOTAL_STREAMS=$(tshark -r "$PCAP_FILE" -T fields -e tcp.stream 2>/dev/null | sort -un | wc -l)

# 2. SYN Packets (SYN=1, ACK=0)
SYN_PACKETS=$(tshark -r "$PCAP_FILE" -Y "tcp.flags.syn==1 && tcp.flags.ack==0" 2>/dev/null | wc -l)

# 3. Streams with RST
RST_STREAMS=$(tshark -r "$PCAP_FILE" -Y "tcp.flags.reset==1" -T fields -e tcp.stream 2>/dev/null | sort -u | wc -l)

# 4. Streams with FIN
FIN_STREAMS=$(tshark -r "$PCAP_FILE" -Y "tcp.flags.fin==1" -T fields -e tcp.stream 2>/dev/null | sort -u | wc -l)

# 5. Unanswered SYNs (Streams with SYN but no SYN-ACK)
# Get streams with initial SYN
STREAMS_WITH_SYN=$(tshark -r "$PCAP_FILE" -Y "tcp.flags.syn==1 && tcp.flags.ack==0" -T fields -e tcp.stream 2>/dev/null | sort -u)
# Get streams with SYN-ACK
STREAMS_WITH_SYNACK=$(tshark -r "$PCAP_FILE" -Y "tcp.flags.syn==1 && tcp.flags.ack==1" -T fields -e tcp.stream 2>/dev/null | sort -u)
# Comm distinct: lines in SYN but not in SYNACK
UNANSWERED_SYN_STREAMS=$(comm -23 <(echo "$STREAMS_WITH_SYN") <(echo "$STREAMS_WITH_SYNACK") | wc -l)

# 6 & 7. Largest Stream
# Get stream index with most packets
LARGEST_STREAM_DATA=$(tshark -r "$PCAP_FILE" -T fields -e tcp.stream 2>/dev/null | sort -n | uniq -c | sort -nr | head -1)
LARGEST_STREAM_COUNT=$(echo "$LARGEST_STREAM_DATA" | awk '{print $1}')
LARGEST_STREAM_INDEX=$(echo "$LARGEST_STREAM_DATA" | awk '{print $2}')

echo "Ground Truth Computed:"
echo "  Total Streams: $TOTAL_STREAMS"
echo "  SYN Packets: $SYN_PACKETS"
echo "  RST Streams: $RST_STREAMS"
echo "  FIN Streams: $FIN_STREAMS"
echo "  Unanswered: $UNANSWERED_SYN_STREAMS"
echo "  Largest Stream: $LARGEST_STREAM_INDEX ($LARGEST_STREAM_COUNT packets)"

# Save ground truth to hidden JSON
cat > /tmp/ground_truth.json << EOF
{
    "total_tcp_streams": $TOTAL_STREAMS,
    "syn_packets": $SYN_PACKETS,
    "streams_with_rst": $RST_STREAMS,
    "streams_with_fin": $FIN_STREAMS,
    "unanswered_syn_streams": $UNANSWERED_SYN_STREAMS,
    "largest_stream_index": $LARGEST_STREAM_INDEX,
    "largest_stream_packet_count": $LARGEST_STREAM_COUNT
}
EOF
chmod 600 /tmp/ground_truth.json

# Launch Wireshark
echo "Launching Wireshark..."
su - ga -c "DISPLAY=:1 wireshark '$PCAP_FILE' > /dev/null 2>&1 &"

# Wait for Wireshark
for i in {1..30}; do
    if wmctrl -l | grep -qi "wireshark"; then
        echo "Wireshark window detected"
        break
    fi
    sleep 1
done

# Maximize and focus
sleep 2
DISPLAY=:1 wmctrl -r "Wireshark" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Wireshark" 2>/dev/null || true

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="