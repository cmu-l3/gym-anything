#!/bin/bash
set -e
echo "=== Exporting TCP Retransmission Analysis results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Paths
EXPORTED_FILE="/home/ga/Documents/captures/tcp_retransmissions.pcapng"
REPORT_FILE="/home/ga/Documents/captures/retransmission_report.txt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Load Ground Truth
GT_COUNT=$(cat /tmp/ground_truth_count.txt 2>/dev/null || echo "0")
GT_TOP_IP=$(cat /tmp/ground_truth_top_ip.txt 2>/dev/null || echo "")
GT_TOTAL=$(cat /tmp/ground_truth_total_packets.txt 2>/dev/null || echo "0")

# --- Analyze Exported PCAP ---
EXPORTED_EXISTS="false"
EXPORTED_MOD_TIME="0"
EXPORTED_PACKET_COUNT=0
EXPORTED_NON_RETRANS_COUNT=0
EXPORTED_VALID="false"

if [ -s "$EXPORTED_FILE" ]; then
    EXPORTED_EXISTS="true"
    EXPORTED_MOD_TIME=$(stat -c %Y "$EXPORTED_FILE" 2>/dev/null || echo "0")
    
    # Validate PCAP structure and count packets
    if tshark -r "$EXPORTED_FILE" 2>/dev/null > /dev/null; then
        EXPORTED_VALID="true"
        EXPORTED_PACKET_COUNT=$(tshark -r "$EXPORTED_FILE" 2>/dev/null | wc -l)
        
        # Check purity: How many packets are NOT retransmissions?
        # Note: We filter for packets that do NOT match the retransmission filter
        EXPORTED_NON_RETRANS_COUNT=$(tshark -r "$EXPORTED_FILE" -Y "!(tcp.analysis.retransmission)" 2>/dev/null | wc -l)
    else
        EXPORTED_VALID="false"
    fi
fi

# --- Analyze Report File ---
REPORT_EXISTS="false"
REPORT_MOD_TIME="0"
REPORT_CONTENT_COUNT=""
REPORT_CONTENT_IP=""
REPORT_RAW_CONTENT=""

if [ -s "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_MOD_TIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    REPORT_RAW_CONTENT=$(cat "$REPORT_FILE" | head -c 500) # Limit size for JSON safety
    
    # Try to parse number
    REPORT_CONTENT_COUNT=$(grep -i "Total Retransmissions" "$REPORT_FILE" 2>/dev/null | grep -oP '\d+' | head -1 || echo "")
    
    # Try to parse IP
    REPORT_CONTENT_IP=$(grep -i "Top Source IP" "$REPORT_FILE" 2>/dev/null | grep -oP '\d+\.\d+\.\d+\.\d+' | head -1 || echo "")
fi

# Create result JSON
# We use Python to ensure valid JSON formatting and handle potential string escaping issues
python3 -c "
import json
import os
import sys

data = {
    'task_start_timestamp': $TASK_START,
    'ground_truth': {
        'count': int('$GT_COUNT'),
        'top_ip': '$GT_TOP_IP',
        'total_original_packets': int('$GT_TOTAL')
    },
    'exported_file': {
        'exists': '$EXPORTED_EXISTS' == 'true',
        'valid_pcap': '$EXPORTED_VALID' == 'true',
        'mod_timestamp': int('$EXPORTED_MOD_TIME'),
        'packet_count': int('$EXPORTED_PACKET_COUNT'),
        'non_retrans_count': int('$EXPORTED_NON_RETRANS_COUNT')
    },
    'report_file': {
        'exists': '$REPORT_EXISTS' == 'true',
        'mod_timestamp': int('$REPORT_MOD_TIME'),
        'parsed_count': '$REPORT_CONTENT_COUNT',
        'parsed_ip': '$REPORT_CONTENT_IP'
    },
    'screenshot_path': '/tmp/task_final_state.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(data, f, indent=2)
"

# Handle permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="