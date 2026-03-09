#!/bin/bash
set -e

echo "=== Setting up DNS Recursion Policy Audit task ==="

# Define paths
PCAP_FILE="/home/ga/Documents/captures/dns.cap"
GROUND_TRUTH_FILE="/tmp/dns_audit_ground_truth.json"

# Ensure the PCAP file exists
if [ ! -f "$PCAP_FILE" ]; then
    echo "ERROR: PCAP file $PCAP_FILE not found!"
    exit 1
fi

# Clean up previous artifacts
rm -f /home/ga/Documents/captures/recursive_queries.pcap
rm -f /home/ga/Documents/captures/dns_audit_report.json
rm -f "$GROUND_TRUTH_FILE"
rm -f /tmp/task_result.json

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# --- Calculate Ground Truth (Hidden from Agent) ---
echo "Calculating ground truth metrics..."

# 1. Total packets
GT_TOTAL=$(tshark -r "$PCAP_FILE" 2>/dev/null | wc -l)

# 2. Count packets with Recursion Desired (RD) bit set
GT_RD_COUNT=$(tshark -r "$PCAP_FILE" -Y "dns.flags.rd == 1" 2>/dev/null | wc -l)

# 3. Count packets with Recursion Available (RA) bit set
GT_RA_COUNT=$(tshark -r "$PCAP_FILE" -Y "dns.flags.ra == 1" 2>/dev/null | wc -l)

# 4. Determine if server supports recursion (if RA count > 0)
if [ "$GT_RA_COUNT" -gt 0 ]; then
    GT_SUPPORTS_RECURSION="true"
else
    GT_SUPPORTS_RECURSION="false"
fi

# Save ground truth to a JSON file
cat > "$GROUND_TRUTH_FILE" << EOF
{
    "total_packets": $GT_TOTAL,
    "recursive_queries_count": $GT_RD_COUNT,
    "recursion_available_count": $GT_RA_COUNT,
    "server_supports_recursion": $GT_SUPPORTS_RECURSION
}
EOF

echo "Ground Truth Calculated: Total=$GT_TOTAL, RD=$GT_RD_COUNT, RA=$GT_RA_COUNT"

# --- Setup Application State ---

# Start Wireshark with the file loaded
echo "Starting Wireshark..."
if ! pgrep -f "wireshark" > /dev/null; then
    su - ga -c "DISPLAY=:1 wireshark $PCAP_FILE > /dev/null 2>&1 &"
    
    # Wait for window to appear
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "wireshark"; then
            echo "Wireshark window detected"
            break
        fi
        sleep 1
    done
    sleep 2
fi

# Maximize the window
DISPLAY=:1 wmctrl -r "Wireshark" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
echo "Capturing initial state..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="