#!/bin/bash
set -e

echo "=== Setting up TCP RTT Latency Analysis Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

PCAP_FILE="/home/ga/Documents/captures/200722_tcp_anon.pcapng"

if [ ! -f "$PCAP_FILE" ]; then
    echo "ERROR: Required PCAP file not found: $PCAP_FILE"
    exit 1
fi

# Reset Wireshark configuration to ensure no pre-existing custom columns
# We want the agent to add them, not find them already there
rm -rf /home/ga/.config/wireshark/recent
rm -rf /home/ga/.config/wireshark/preferences
mkdir -p /home/ga/.config/wireshark

# Create basic preferences to suppress dialogs
cat > /home/ga/.config/wireshark/preferences << 'EOF'
gui.update.enabled: FALSE
gui.ask_unsaved: FALSE
gui.setup_welcome_window: FALSE
EOF

# Pre-calculate Ground Truth (hidden from agent)
# Find packet with max RTT
# Format: frame.number | tcp.analysis.ack_rtt | tcp.stream
# We filter for tcp.analysis.ack_rtt to ensure field exists
echo "Calculating ground truth..."
MAX_RTT_DATA=$(tshark -r "$PCAP_FILE" -Y "tcp.analysis.ack_rtt" -T fields -e frame.number -e tcp.analysis.ack_rtt -e tcp.stream | sort -k2 -gr | head -1)

MAX_PKT=$(echo "$MAX_RTT_DATA" | awk '{print $1}')
MAX_VAL=$(echo "$MAX_RTT_DATA" | awk '{print $2}')
MAX_STREAM=$(echo "$MAX_RTT_DATA" | awk '{print $3}')

echo "Ground Truth: Packet=$MAX_PKT, RTT=$MAX_VAL, Stream=$MAX_STREAM"

# Save ground truth for export script
cat > /tmp/ground_truth.json << EOF
{
    "packet_number": "$MAX_PKT",
    "rtt_value": "$MAX_VAL",
    "stream_index": "$MAX_STREAM"
}
EOF

# Ensure no previous output files exist
rm -f /home/ga/Documents/captures/latency_report.txt
rm -f /home/ga/Documents/captures/slow_stream.pcapng

# Start Wireshark
echo "Starting Wireshark..."
su - ga -c "DISPLAY=:1 wireshark '$PCAP_FILE' > /dev/null 2>&1 &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Wireshark"; then
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r "Wireshark" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Capture initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="