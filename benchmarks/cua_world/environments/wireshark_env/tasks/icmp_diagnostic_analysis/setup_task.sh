#!/bin/bash
set -e

echo "=== Setting up ICMP Diagnostic Analysis Task ==="

# 1. Prepare Directory and File Paths
CAPTURE_DIR="/home/ga/Documents/captures"
CAPTURE_FILE="$CAPTURE_DIR/icmp_diagnostics.pcapng"
REPORT_FILE="/home/ga/Documents/icmp_analysis_report.txt"
GROUND_TRUTH_DIR="/var/lib/wireshark_task/ground_truth"

mkdir -p "$CAPTURE_DIR"
mkdir -p "$GROUND_TRUTH_DIR"

# Clean up previous run artifacts
rm -f "$CAPTURE_FILE" "$REPORT_FILE" /tmp/task_result.json

# 2. Generate Real Traffic (The "Real Data" Requirement)
echo "Generating live network traffic..."

# Start capturing in background
# -w: write to file
# -i any: capture on all interfaces
# -s 0: full packet size
# icmp: filter only ICMP traffic
tcpdump -i any -s 0 -w "$CAPTURE_FILE" icmp &
TCPDUMP_PID=$!

sleep 2

# Traffic Pattern A: Standard Ping (Echo Req/Rep) to Google DNS
# This provides the RTT data
echo "Generating Pings..."
ping -c 10 -i 0.2 8.8.8.8 || ping -c 10 -i 0.2 127.0.0.1

# Traffic Pattern B: Traceroute (Time Exceeded)
# This provides the "Unique Hops" data
# -n: no dns lookup (faster), -m 15: max 15 hops, -w 1: wait 1s
echo "Generating Traceroute..."
traceroute -n -m 15 -w 1 8.8.8.8 || true

# Traffic Pattern C: Unreachable Destination (Dest Unreachable)
# 198.51.100.0/24 is TEST-NET-2, reserved for documentation/examples
# and should not be reachable on the public internet.
echo "Generating Unreachables..."
ping -c 3 -W 1 198.51.100.1 || true

# Wait a moment for buffers to flush
sleep 2

# Stop capture
kill "$TCPDUMP_PID" 2>/dev/null || true
wait "$TCPDUMP_PID" 2>/dev/null || true

# Set permissions
chown ga:ga "$CAPTURE_FILE"
chmod 644 "$CAPTURE_FILE"

# 3. Compute Ground Truth (Hidden from Agent)
echo "Computing ground truth..."

# Helper function to run tshark on the capture
run_tshark() {
    tshark -r "$CAPTURE_FILE" "$@" 2>/dev/null
}

# A. Total ICMP Packets
TOTAL_COUNT=$(run_tshark -Y "icmp" | wc -l)
echo "$TOTAL_COUNT" > "$GROUND_TRUTH_DIR/total_count.txt"

# B. Type Counts (JSON map)
# Output format from tshark: "8", "0", "11", etc.
# Python used to robustly count and format as JSON
run_tshark -Y "icmp" -T fields -e icmp.type | python3 -c "
import sys, json, collections
counts = collections.Counter(sys.stdin.read().splitlines())
# filter empty lines
counts = {k: v for k, v in counts.items() if k.strip()}
print(json.dumps(counts))
" > "$GROUND_TRUTH_DIR/type_counts.json"

# C. Average RTT to 8.8.8.8 (using Echo Replies)
# Wireshark calculates 'icmp.resptime' in milliseconds for us matching req/rep
# We filter for Echo Reply (Type 0) from 8.8.8.8
AVG_RTT=$(run_tshark -Y "icmp.type==0 && ip.src==8.8.8.8" -T fields -e icmp.resptime | awk '{ sum += $1; n++ } END { if (n > 0) print sum / n; else print "0" }')
echo "$AVG_RTT" > "$GROUND_TRUTH_DIR/avg_rtt.txt"

# D. Unique Traceroute Hops
# Filter for Time Exceeded (Type 11) and count unique Source IPs
UNIQUE_HOPS=$(run_tshark -Y "icmp.type==11" -T fields -e ip.src | sort | uniq | wc -l)
echo "$UNIQUE_HOPS" > "$GROUND_TRUTH_DIR/unique_hops.txt"

# E. Unreachable IPs
# Filter for Dest Unreachable (Type 3)
UNREACHABLE_IPS=$(run_tshark -Y "icmp.type==3" -T fields -e ip.dst | sort | uniq | tr '\n' ',')
echo "$UNREACHABLE_IPS" > "$GROUND_TRUTH_DIR/unreachable_ips.txt"

echo "Ground Truth Generated:"
echo "  Total: $TOTAL_COUNT"
echo "  Avg RTT: $AVG_RTT"
echo "  Hops: $UNIQUE_HOPS"

# 4. Launch Wireshark
echo "Launching Wireshark..."
su - ga -c "DISPLAY=:1 wireshark $CAPTURE_FILE > /dev/null 2>&1 &"

# Wait for window and maximize
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Wireshark"; then
        echo "Wireshark window found."
        break
    fi
    sleep 1
done

DISPLAY=:1 wmctrl -r "Wireshark" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Record start time
date +%s > /tmp/task_start_time.txt

# Initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="