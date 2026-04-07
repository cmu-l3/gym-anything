#!/bin/bash
set -e

echo "=== Setting up detect_latency_spikes_tcp_delta task ==="

# Source shared utilities if available
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
fi

# Clean up previous artifacts
rm -f /home/ga/Documents/captures/latency_spikes.pcapng 2>/dev/null || true
rm -f /home/ga/Documents/captures/latency_report.txt 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

PCAP_PATH="/home/ga/Documents/captures/200722_tcp_anon.pcapng"

# Ensure PCAP exists
if [ ! -f "$PCAP_PATH" ]; then
    echo "ERROR: Required PCAP file not found at $PCAP_PATH"
    # Try to copy from backup or download if missing (fail-safe)
    if [ -f /usr/share/doc/wireshark-common/examples/200722_tcp_anon.pcapng ]; then
        cp /usr/share/doc/wireshark-common/examples/200722_tcp_anon.pcapng "$PCAP_PATH"
    else
        echo "Fatal: Cannot locate 200722_tcp_anon.pcapng"
        exit 1
    fi
fi

# Pre-calculate ground truth to ensure the task is solvable and data is valid
echo "Calculating ground truth..."
# Ensure tshark uses the same prefs as we expect (timestamp calculation is usually default in tshark/wireshark recent versions, but we force it)
# We want tcp.time_delta > 0.2
THRESHOLD="0.2"

# 1. Total Count
GT_COUNT=$(tshark -r "$PCAP_PATH" -Y "tcp.time_delta > $THRESHOLD" 2>/dev/null | wc -l)

# 2. Max Delta and Stream Index
# Output format: stream_index <tab> time_delta. Sort by delta descending.
GT_MAX_DATA=$(tshark -r "$PCAP_PATH" -Y "tcp.time_delta > $THRESHOLD" -T fields -e tcp.stream -e tcp.time_delta 2>/dev/null | sort -k2 -n -r | head -1)
GT_STREAM=$(echo "$GT_MAX_DATA" | awk '{print $1}')
GT_MAX_DELTA=$(echo "$GT_MAX_DATA" | awk '{print $2}')

echo "Ground Truth: Count=$GT_COUNT, WorstStream=$GT_STREAM, MaxDelta=$GT_MAX_DELTA"

# Store ground truth in a hidden file for export_result.sh to use
cat > /tmp/.ground_truth_latency.json << EOF
{
    "gt_count": $GT_COUNT,
    "gt_stream": "$GT_STREAM",
    "gt_max_delta": "$GT_MAX_DELTA"
}
EOF
chmod 600 /tmp/.ground_truth_latency.json

# Launch Wireshark
echo "Launching Wireshark..."
if ! pgrep -f "wireshark" > /dev/null; then
    su - ga -c "DISPLAY=:1 wireshark $PCAP_PATH > /dev/null 2>&1 &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "Wireshark"; then
            echo "Wireshark window detected"
            break
        fi
        sleep 1
    done
    sleep 2
fi

# Maximize
DISPLAY=:1 wmctrl -r "Wireshark" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="