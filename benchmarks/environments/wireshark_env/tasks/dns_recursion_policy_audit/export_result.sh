#!/bin/bash
echo "=== Exporting DNS Audit Result ==="

# Source paths
OUTPUT_PCAP="/home/ga/Documents/captures/recursive_queries.pcap"
OUTPUT_REPORT="/home/ga/Documents/captures/dns_audit_report.json"
GROUND_TRUTH_FILE="/tmp/dns_audit_ground_truth.json"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# --- Verify Output PCAP ---
PCAP_EXISTS="false"
PCAP_VALID="false"
PCAP_PACKET_COUNT=0
PCAP_BAD_PACKETS=0
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_PCAP" ]; then
    PCAP_EXISTS="true"
    
    # Check timestamp
    PCAP_MTIME=$(stat -c %Y "$OUTPUT_PCAP" 2>/dev/null || echo "0")
    if [ "$PCAP_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # Validate content with tshark
    # 1. Count total packets in exported file
    PCAP_PACKET_COUNT=$(tshark -r "$OUTPUT_PCAP" 2>/dev/null | wc -l)
    
    # 2. Count packets that should NOT be there (RD == 0)
    # If the filter was applied correctly, this should be 0
    PCAP_BAD_PACKETS=$(tshark -r "$OUTPUT_PCAP" -Y "dns.flags.rd == 0" 2>/dev/null | wc -l)
    
    if [ "$PCAP_PACKET_COUNT" -gt 0 ]; then
        PCAP_VALID="true"
    fi
fi

# --- Verify JSON Report ---
REPORT_EXISTS="false"
REPORT_CONTENT="{}"

if [ -f "$OUTPUT_REPORT" ]; then
    REPORT_EXISTS="true"
    # Read content, default to empty json if read fails
    REPORT_CONTENT=$(cat "$OUTPUT_REPORT" 2>/dev/null || echo "{}")
fi

# Load Ground Truth
GROUND_TRUTH_CONTENT=$(cat "$GROUND_TRUTH_FILE" 2>/dev/null || echo "{}")

# --- Bundle Result for Verifier ---
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "pcap_verification": {
        "exists": $PCAP_EXISTS,
        "valid": $PCAP_VALID,
        "created_during_task": $FILE_CREATED_DURING_TASK,
        "total_packets": $PCAP_PACKET_COUNT,
        "bad_packets_count": $PCAP_BAD_PACKETS
    },
    "report_verification": {
        "exists": $REPORT_EXISTS,
        "content": $REPORT_CONTENT
    },
    "ground_truth": $GROUND_TRUTH_CONTENT
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="