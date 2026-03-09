#!/bin/bash
set -e

echo "=== Setting up export_protocol_hierarchy task ==="

# Clean up any leftover temp files from previous tasks
rm -f /tmp/initial_* /tmp/ground_truth_* /tmp/task_result.json /tmp/task_end.png 2>/dev/null || true

PCAP_FILE="/home/ga/Documents/captures/http.cap"

if [ ! -s "$PCAP_FILE" ]; then
    echo "ERROR: HTTP PCAP file not found or empty at $PCAP_FILE"
    exit 1
fi

# Compute ground truth using tshark protocol hierarchy statistics
echo "Computing ground truth protocol hierarchy..."
tshark -r "$PCAP_FILE" -q -z io,phs 2>/dev/null > /tmp/ground_truth_protocol_hierarchy.txt

# Extract key protocols that should appear in the hierarchy
TOTAL_PACKETS=$(tshark -r "$PCAP_FILE" 2>/dev/null | wc -l)
ETHERNET_PACKETS=$(tshark -r "$PCAP_FILE" -Y "eth" 2>/dev/null | wc -l)
IP_PACKETS=$(tshark -r "$PCAP_FILE" -Y "ip" 2>/dev/null | wc -l)
TCP_PACKETS=$(tshark -r "$PCAP_FILE" -Y "tcp" 2>/dev/null | wc -l)
HTTP_PACKETS=$(tshark -r "$PCAP_FILE" -Y "http" 2>/dev/null | wc -l)
UDP_PACKETS=$(tshark -r "$PCAP_FILE" -Y "udp" 2>/dev/null | wc -l)

echo "Protocol counts: Total=$TOTAL_PACKETS, Eth=$ETHERNET_PACKETS, IP=$IP_PACKETS, TCP=$TCP_PACKETS, HTTP=$HTTP_PACKETS, UDP=$UDP_PACKETS"

# Store protocol presence info
cat > /tmp/ground_truth_protocols.json << EOF
{
    "total_packets": $TOTAL_PACKETS,
    "has_ethernet": $([ "$ETHERNET_PACKETS" -gt 0 ] && echo "true" || echo "false"),
    "has_ip": $([ "$IP_PACKETS" -gt 0 ] && echo "true" || echo "false"),
    "has_tcp": $([ "$TCP_PACKETS" -gt 0 ] && echo "true" || echo "false"),
    "has_http": $([ "$HTTP_PACKETS" -gt 0 ] && echo "true" || echo "false"),
    "has_udp": $([ "$UDP_PACKETS" -gt 0 ] && echo "true" || echo "false"),
    "ethernet_count": $ETHERNET_PACKETS,
    "ip_count": $IP_PACKETS,
    "tcp_count": $TCP_PACKETS,
    "http_count": $HTTP_PACKETS,
    "udp_count": $UDP_PACKETS
}
EOF

# Remove any previous output
rm -f /home/ga/Documents/captures/protocol_hierarchy.txt 2>/dev/null || true

# Open Wireshark with the capture
echo "Opening Wireshark with http.cap..."
su - ga -c "DISPLAY=:1 wireshark /home/ga/Documents/captures/http.cap > /tmp/wireshark_task.log 2>&1 &"

sleep 5

echo "=== Task setup complete ==="
