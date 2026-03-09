#!/bin/bash
set -e

echo "=== Setting up count_dns_queries task ==="

# Clean up any leftover temp files from previous tasks
rm -f /tmp/initial_* /tmp/ground_truth_* /tmp/task_result.json /tmp/task_end.png 2>/dev/null || true

PCAP_FILE="/home/ga/Documents/captures/dns.cap"

if [ ! -s "$PCAP_FILE" ]; then
    echo "ERROR: DNS PCAP file not found or empty at $PCAP_FILE"
    exit 1
fi

# Record ground truth using tshark
TOTAL_PACKETS=$(tshark -r "$PCAP_FILE" 2>/dev/null | wc -l)
DNS_QUERIES=$(tshark -r "$PCAP_FILE" -Y "dns.flags.response == 0" 2>/dev/null | wc -l)
DNS_RESPONSES=$(tshark -r "$PCAP_FILE" -Y "dns.flags.response == 1" 2>/dev/null | wc -l)

echo "$TOTAL_PACKETS" > /tmp/initial_total_packets
echo "$DNS_QUERIES" > /tmp/ground_truth_dns_queries
echo "$DNS_RESPONSES" > /tmp/initial_dns_responses

echo "Ground truth: $TOTAL_PACKETS total, $DNS_QUERIES queries, $DNS_RESPONSES responses"

# Remove any previous output
rm -f /home/ga/Documents/captures/dns_query_count.txt 2>/dev/null || true

# Open Wireshark with the DNS capture
echo "Opening Wireshark with dns.cap..."
su - ga -c "DISPLAY=:1 wireshark /home/ga/Documents/captures/dns.cap > /tmp/wireshark_task.log 2>&1 &"

sleep 5

echo "=== Task setup complete ==="
