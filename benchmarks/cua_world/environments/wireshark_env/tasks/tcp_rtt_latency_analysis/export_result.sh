#!/bin/bash
set -e

echo "=== Exporting TCP RTT Latency Analysis Result ==="

source /workspace/scripts/task_utils.sh

# Capture final state
take_screenshot /tmp/task_final.png

# Paths
REPORT_FILE="/home/ga/Documents/captures/latency_report.txt"
EXPORT_FILE="/home/ga/Documents/captures/slow_stream.pcapng"
PREFS_FILE="/home/ga/.config/wireshark/preferences"
RECENT_FILE="/home/ga/.config/wireshark/recent"

# Load Ground Truth
GT_PKT=$(python3 -c "import json; print(json.load(open('/tmp/ground_truth.json'))['packet_number'])")
GT_RTT=$(python3 -c "import json; print(json.load(open('/tmp/ground_truth.json'))['rtt_value'])")
GT_STREAM=$(python3 -c "import json; print(json.load(open('/tmp/ground_truth.json'))['stream_index'])")

# 1. Analyze Report File
REPORT_EXISTS="false"
USER_PKT=""
USER_RTT=""
USER_STREAM=""

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    CONTENT=$(cat "$REPORT_FILE")
    # Extract values using grep/awk
    USER_PKT=$(echo "$CONTENT" | grep "max_rtt_packet_number" | cut -d: -f2 | tr -d '[:space:]')
    USER_RTT=$(echo "$CONTENT" | grep "max_rtt_value_seconds" | cut -d: -f2 | tr -d '[:space:]')
    USER_STREAM=$(echo "$CONTENT" | grep "bad_stream_index" | cut -d: -f2 | tr -d '[:space:]')
fi

# 2. Analyze Exported PCAP
EXPORT_EXISTS="false"
EXPORT_HAS_TARGET_PACKET="false"
EXPORT_IS_SINGLE_STREAM="false"
EXPORT_STREAM_ID=""

if [ -f "$EXPORT_FILE" ]; then
    EXPORT_EXISTS="true"
    
    # Check if the max RTT packet is in the file
    if tshark -r "$EXPORT_FILE" -Y "frame.number == $GT_PKT" 2>/dev/null | grep -q .; then
        # Note: frame numbers change in new capture, so we check if a packet with 
        # the same timestamp and relative sequence exists, OR we trust the agent filtered correctly.
        # Better approach: Check if the file contains the correct stream content.
        # We'll check if ALL packets in the exported file belong to the target stream index
        # BUT stream index might reset to 0 in a new file if it's the only stream.
        # Instead, we check the IPs/Ports of the ground truth stream.
        
        # Get source/dest of ground truth stream from original file
        STREAM_FILTER="tcp.stream eq $GT_STREAM"
        GT_IPS=$(tshark -r /home/ga/Documents/captures/200722_tcp_anon.pcapng -Y "$STREAM_FILTER" -T fields -e ip.src -e ip.dst | head -1)
        GT_SRC=$(echo $GT_IPS | awk '{print $1}')
        GT_DST=$(echo $GT_IPS | awk '{print $2}')
        
        # Check if exported file matches these IPs
        EXPORT_IPS=$(tshark -r "$EXPORT_FILE" -T fields -e ip.src -e ip.dst | head -1)
        EXP_SRC=$(echo $EXPORT_IPS | awk '{print $1}')
        
        if [[ "$EXP_SRC" == "$GT_SRC" || "$EXP_SRC" == "$GT_DST" ]]; then
             EXPORT_HAS_TARGET_PACKET="true"
        fi
    fi
    
    # Check for Stream Isolation (only one TCP stream should be present)
    STREAM_COUNT=$(tshark -r "$EXPORT_FILE" -T fields -e tcp.stream | sort | uniq | wc -l)
    if [ "$STREAM_COUNT" -eq 1 ]; then
        EXPORT_IS_SINGLE_STREAM="true"
    fi
fi

# 3. Check UI Configuration (Custom Columns)
# Columns are saved in 'recent' file under 'gui.column.format' usually, or 'preferences'
HAS_RTT_COLUMN="false"
HAS_STREAM_COLUMN="false"

# Search both files
if grep -r "tcp.analysis.ack_rtt" /home/ga/.config/wireshark/ 2>/dev/null | grep -q "column"; then
    HAS_RTT_COLUMN="true"
fi

if grep -r "tcp.stream" /home/ga/.config/wireshark/ 2>/dev/null | grep -q "column"; then
    HAS_STREAM_COLUMN="true"
fi

# JSON Export
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "ground_truth": {
        "packet": "$GT_PKT",
        "rtt": "$GT_RTT",
        "stream": "$GT_STREAM"
    },
    "user_report": {
        "exists": $REPORT_EXISTS,
        "packet": "$USER_PKT",
        "rtt": "$USER_RTT",
        "stream": "$USER_STREAM"
    },
    "export_file": {
        "exists": $EXPORT_EXISTS,
        "correct_content": $EXPORT_HAS_TARGET_PACKET,
        "is_single_stream": $EXPORT_IS_SINGLE_STREAM
    },
    "config": {
        "has_rtt_column": $HAS_RTT_COLUMN,
        "has_stream_column": $HAS_STREAM_COLUMN
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="