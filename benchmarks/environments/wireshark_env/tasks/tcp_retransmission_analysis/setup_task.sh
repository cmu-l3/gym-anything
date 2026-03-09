#!/bin/bash
set -e
echo "=== Setting up TCP Retransmission Analysis task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming detection
date +%s > /tmp/task_start_time.txt

# Clean up any previous task artifacts
rm -f /home/ga/Documents/captures/tcp_retransmissions.pcapng
rm -f /home/ga/Documents/captures/retransmission_report.txt
rm -f /tmp/ground_truth_*.txt
rm -f /tmp/task_result.json

# Compute and store ground truth (hidden from agent in /tmp)
PCAP_FILE="/home/ga/Documents/captures/200722_tcp_anon.pcapng"

if [ ! -s "$PCAP_FILE" ]; then
    echo "ERROR: Source PCAP file not found or empty: $PCAP_FILE"
    exit 1
fi

echo "Computing ground truth..."

# Ground truth: total retransmission count
GT_COUNT=$(tshark -r "$PCAP_FILE" -Y "tcp.analysis.retransmission" 2>/dev/null | wc -l)
echo "$GT_COUNT" > /tmp/ground_truth_count.txt

# Ground truth: top source IP by retransmission count
GT_TOP_IP=$(tshark -r "$PCAP_FILE" -Y "tcp.analysis.retransmission" -T fields -e ip.src 2>/dev/null \
    | sort | uniq -c | sort -rn | head -1 | awk '{print $2}')
echo "$GT_TOP_IP" > /tmp/ground_truth_top_ip.txt

# Ground truth: total packet count in original file (to ensure subset export)
GT_TOTAL=$(tshark -r "$PCAP_FILE" 2>/dev/null | wc -l)
echo "$GT_TOTAL" > /tmp/ground_truth_total_packets.txt

echo "Ground truth computed: $GT_COUNT retransmissions out of $GT_TOTAL packets, top IP: $GT_TOP_IP"

# Kill any existing Wireshark instances
pkill -f wireshark 2>/dev/null || true
sleep 2

# Launch Wireshark with the capture file
echo "Launching Wireshark with $PCAP_FILE ..."
su - ga -c "DISPLAY=:1 wireshark '$PCAP_FILE' > /dev/null 2>&1 &"

# Wait for Wireshark window to appear
echo "Waiting for Wireshark window..."
for i in {1..40}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i -E "wireshark|200722_tcp_anon"; then
        echo "Wireshark window detected."
        break
    fi
    sleep 1
done

sleep 3

# Maximize and focus Wireshark
# Use slightly different calls to ensure it catches the window
DISPLAY=:1 wmctrl -r "Wireshark" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Wireshark" 2>/dev/null || true

# Dismiss any startup dialogs if they exist
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take screenshot of initial state
take_screenshot /tmp/task_initial_state.png

echo "=== TCP Retransmission Analysis task setup complete ==="