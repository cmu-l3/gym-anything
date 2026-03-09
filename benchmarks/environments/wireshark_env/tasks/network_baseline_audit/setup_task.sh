#!/bin/bash
# Setup script for Network Baseline Audit task
echo "=== Setting up Network Baseline Audit ==="

. /workspace/scripts/task_utils.sh

if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        local path="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 scrot "$path" 2>/dev/null || DISPLAY=:1 import -window root "$path" 2>/dev/null || true
    }
fi

rm -f /tmp/task_result.json /tmp/ground_truth_* /tmp/initial_* /tmp/task_start_*

CAPTURES_DIR="/home/ga/Documents/captures"
MERGED_PCAP="$CAPTURES_DIR/baseline_audit.pcapng"

# Create a merged capture from multiple source PCAPs for distinct starting data
# This gives the agent a richer, multi-protocol capture to analyze
echo "Creating merged capture for baseline audit..."
rm -f "$MERGED_PCAP"

# mergecap is part of the Wireshark installation
MERGE_FILES=""
for f in "$CAPTURES_DIR/http.cap" "$CAPTURES_DIR/dns.cap" "$CAPTURES_DIR/200722_tcp_anon.pcapng"; do
    if [ -f "$f" ]; then
        MERGE_FILES="$MERGE_FILES $f"
    fi
done

if [ -n "$MERGE_FILES" ]; then
    mergecap -w "$MERGED_PCAP" $MERGE_FILES 2>/dev/null
    chown ga:ga "$MERGED_PCAP" 2>/dev/null
    chmod 644 "$MERGED_PCAP" 2>/dev/null
fi

if [ ! -f "$MERGED_PCAP" ]; then
    echo "ERROR: Could not create merged capture!"
    # Fallback: use the TCP capture as-is
    cp "$CAPTURES_DIR/200722_tcp_anon.pcapng" "$MERGED_PCAP" 2>/dev/null
fi

rm -f /home/ga/Documents/captures/baseline_audit_report.txt

# --- Compute ground truth using tshark ---

# Protocol list (from protocol hierarchy)
GT_PROTOCOLS=$(tshark -r "$MERGED_PCAP" -q -z io,phs 2>/dev/null | grep -oP '^\s+\S+' | awk '{print $1}' | sort -u | grep -v "^$")
# Also get protocol names from packet dissection
GT_PROTO_NAMES=$(tshark -r "$MERGED_PCAP" -T fields -e frame.protocols 2>/dev/null | tr ':' '\n' | sort -u | grep -v "^$")
echo "$GT_PROTO_NAMES" > /tmp/ground_truth_baseline_protocols

# Unique IP endpoints
GT_IPS=$(tshark -r "$MERGED_PCAP" -T fields -e ip.src -e ip.dst 2>/dev/null | tr '\t' '\n' | sort -u | grep -v "^$" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$')
echo "$GT_IPS" > /tmp/ground_truth_baseline_ips

# Unique destination ports
GT_DST_PORTS=$(tshark -r "$MERGED_PCAP" -T fields -e tcp.dstport -e udp.dstport 2>/dev/null | tr '\t' '\n' | sort -un | grep -v "^$")
echo "$GT_DST_PORTS" > /tmp/ground_truth_baseline_ports

# TCP retransmissions
GT_RETRANS=$(tshark -r "$MERGED_PCAP" -Y "tcp.analysis.retransmission" 2>/dev/null | wc -l)
echo "$GT_RETRANS" > /tmp/ground_truth_baseline_retransmissions

# Total packet count
GT_TOTAL_PACKETS=$(tshark -r "$MERGED_PCAP" 2>/dev/null | wc -l)
echo "$GT_TOTAL_PACKETS" > /tmp/ground_truth_baseline_total_packets

# Total bytes (from capture file properties)
GT_TOTAL_BYTES=$(tshark -r "$MERGED_PCAP" -T fields -e frame.len 2>/dev/null | awk '{sum+=$1} END {print sum}')
echo "$GT_TOTAL_BYTES" > /tmp/ground_truth_baseline_total_bytes

date +%s > /tmp/task_start_timestamp

echo "Ground truth computed:"
echo "  Protocols: $(echo "$GT_PROTO_NAMES" | wc -l) unique"
echo "  IPs: $(echo "$GT_IPS" | wc -l) unique"
echo "  Dest ports: $(echo "$GT_DST_PORTS" | wc -l) unique"
echo "  Retransmissions: $GT_RETRANS"
echo "  Total packets: $GT_TOTAL_PACKETS"
echo "  Total bytes: $GT_TOTAL_BYTES"

# Launch Wireshark
pkill -f wireshark 2>/dev/null || true
sleep 1
su - ga -c "DISPLAY=:1 wireshark '$MERGED_PCAP' > /tmp/wireshark_task.log 2>&1 &"
sleep 5

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
