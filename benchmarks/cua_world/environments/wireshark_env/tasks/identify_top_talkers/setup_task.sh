#!/bin/bash
set -e

echo "=== Setting up identify_top_talkers task ==="

# Clean up any leftover temp files from previous tasks
rm -f /tmp/initial_* /tmp/ground_truth_* /tmp/task_result.json /tmp/task_end.png /tmp/endpoint_stats_raw.txt /tmp/all_senders_ranked.txt 2>/dev/null || true

PCAP_FILE="/home/ga/Documents/captures/200722_tcp_anon.pcapng"

if [ ! -s "$PCAP_FILE" ]; then
    echo "ERROR: TCP PCAP file not found or empty at $PCAP_FILE"
    exit 1
fi

# Compute ground truth: find the IP endpoint with the highest bytes sent
# tshark -z endpoints,ip gives us endpoint statistics
# We extract the IP with highest Tx Bytes
echo "Computing ground truth endpoint statistics..."

# Get IP endpoint stats for reference
ENDPOINT_STATS=$(tshark -r "$PCAP_FILE" -q -z endpoints,ip 2>/dev/null)
echo "$ENDPOINT_STATS" > /tmp/endpoint_stats_raw.txt

# Compute ground truth using IP-layer bytes (ip.len), matching what
# the Wireshark GUI Endpoints dialog shows as "Tx Bytes"
TOP_SENDER=$(tshark -r "$PCAP_FILE" -T fields -e ip.src -e ip.len 2>/dev/null | \
    awk -F'\t' '$1!="" && $2!="" {bytes[$1]+=$2} END {max=0; for(ip in bytes) {if(bytes[ip]>max){max=bytes[ip]; top=ip}} print top}')

echo "$TOP_SENDER" > /tmp/ground_truth_top_talker
echo "Ground truth top sender (by IP-layer Tx Bytes): $TOP_SENDER"

# Also store all IPs and their byte counts for partial credit
tshark -r "$PCAP_FILE" -T fields -e ip.src -e ip.len 2>/dev/null | \
    awk -F'\t' '$1!="" && $2!="" {bytes[$1]+=$2} END {for(ip in bytes) print ip, bytes[ip]}' | \
    sort -k2 -n -r > /tmp/all_senders_ranked.txt

echo "Top 5 senders by bytes:"
head -5 /tmp/all_senders_ranked.txt

# Remove any previous output
rm -f /home/ga/Documents/captures/top_talker.txt 2>/dev/null || true

# Open Wireshark with the capture file
echo "Opening Wireshark with 200722_tcp_anon.pcapng..."
su - ga -c "DISPLAY=:1 wireshark /home/ga/Documents/captures/200722_tcp_anon.pcapng > /tmp/wireshark_task.log 2>&1 &"

sleep 5

echo "=== Task setup complete ==="
