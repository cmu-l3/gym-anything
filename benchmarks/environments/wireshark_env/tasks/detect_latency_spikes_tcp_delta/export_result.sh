#!/bin/bash
set -e

echo "=== Exporting detect_latency_spikes_tcp_delta results ==="

# Timestamp
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
OUTPUT_PCAP="/home/ga/Documents/captures/latency_spikes.pcapng"
OUTPUT_REPORT="/home/ga/Documents/captures/latency_report.txt"
PCAP_SOURCE="/home/ga/Documents/captures/200722_tcp_anon.pcapng"

# Load Ground Truth
GT_FILE="/tmp/.ground_truth_latency.json"
if [ -f "$GT_FILE" ]; then
    GT_COUNT=$(grep -o '"gt_count": [0-9]*' $GT_FILE | cut -d' ' -f2)
    GT_STREAM=$(grep -o '"gt_stream": "[^"]*"' $GT_FILE | cut -d'"' -f4)
    GT_MAX_DELTA=$(grep -o '"gt_max_delta": "[^"]*"' $GT_FILE | cut -d'"' -f4)
else
    # Fallback calculation if hidden file missing
    GT_COUNT=$(tshark -r "$PCAP_SOURCE" -Y "tcp.time_delta > 0.2" 2>/dev/null | wc -l)
    GT_MAX_DATA=$(tshark -r "$PCAP_SOURCE" -Y "tcp.time_delta > 0.2" -T fields -e tcp.stream -e tcp.time_delta 2>/dev/null | sort -k2 -n -r | head -1)
    GT_STREAM=$(echo "$GT_MAX_DATA" | awk '{print $1}')
    GT_MAX_DELTA=$(echo "$GT_MAX_DATA" | awk '{print $2}')
fi

# --- Verify Output PCAP ---
PCAP_EXISTS="false"
PCAP_VALID="false"
PCAP_FALSE_POSITIVES=0
PCAP_COUNT=0

if [ -f "$OUTPUT_PCAP" ]; then
    PCAP_EXISTS="true"
    # Check modification time
    PCAP_MTIME=$(stat -c %Y "$OUTPUT_PCAP" 2>/dev/null || echo "0")
    
    # Analyze the user's exported file
    # 1. Count packets
    PCAP_COUNT=$(tshark -r "$OUTPUT_PCAP" 2>/dev/null | wc -l)
    
    # 2. Check for false positives (packets <= 0.2 delta)
    # Note: When exporting specific packets, Wireshark keeps the original timestamps/deltas relative to the stream in the new file usually? 
    # Actually, tcp.time_delta is calculated dynamically. If we export ONLY the spike packets, 
    # the delta in the NEW file might be different because the "previous" packet is missing.
    # HOWEVER, the verifier needs to know if the agent exported the *correct* packets.
    # We can match by frame number or roughly by count. 
    # A better check: Does the user's file contain the packet with the MAX delta from the original?
    
    # Let's check if the worst offender is in the file
    WORST_PACKET_PRESENT="false"
    # We identify the worst packet by its timestamp or specific TCP sequence, but simpler is to check if the max delta in the *new* file is high.
    # Actually, just checking the count matches ground truth is a strong signal for the pcap.
    
    # Let's stick to count matching for the PCAP verification primarily.
fi

# --- Verify Report ---
REPORT_EXISTS="false"
REPORT_CONTENT=""
USER_COUNT=""
USER_STREAM=""
USER_DELTA=""

if [ -f "$OUTPUT_REPORT" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$OUTPUT_REPORT")
    
    # Parse key-values (case insensitive, allowing loose formatting)
    USER_COUNT=$(grep -i "total_spike_packets" "$OUTPUT_REPORT" | grep -o "[0-9]*" | head -1 || echo "")
    USER_STREAM=$(grep -i "worst_stream_index" "$OUTPUT_REPORT" | grep -o "[0-9]*" | head -1 || echo "")
    # Extract delta (floating point)
    USER_DELTA=$(grep -i "max_delta_seconds" "$OUTPUT_REPORT" | grep -o "[0-9]*\.[0-9]*" | head -1 || echo "")
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Construct JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "pcap_exists": $PCAP_EXISTS,
    "pcap_packet_count": ${PCAP_COUNT:-0},
    "report_exists": $REPORT_EXISTS,
    "user_count": "${USER_COUNT}",
    "user_stream": "${USER_STREAM}",
    "user_delta": "${USER_DELTA}",
    "gt_count": ${GT_COUNT:-0},
    "gt_stream": "${GT_STREAM}",
    "gt_max_delta": "${GT_MAX_DELTA}",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="