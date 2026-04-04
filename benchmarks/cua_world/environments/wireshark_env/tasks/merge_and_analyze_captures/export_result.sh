#!/bin/bash
set -e

echo "=== Exporting merge_and_analyze_captures result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
OUTPUT_PCAP="/home/ga/Documents/captures/merged_traffic.pcapng"
OUTPUT_REPORT="/home/ga/Documents/captures/merge_report.txt"
GROUND_TRUTH_FILE="/tmp/ground_truth.json"

# --- Analyze the Merged PCAP ---
PCAP_EXISTS="false"
PCAP_VALID="false"
PCAP_PACKET_COUNT=0
PCAP_PROTOCOLS=""
IS_CHRONOLOGICAL="false"
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_PCAP" ]; then
    PCAP_EXISTS="true"
    
    # Check timestamp
    PCAP_MTIME=$(stat -c %Y "$OUTPUT_PCAP" 2>/dev/null || echo "0")
    if [ "$PCAP_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # Check validity and count packets
    if tshark -r "$OUTPUT_PCAP" -c 1 > /dev/null 2>&1; then
        PCAP_VALID="true"
        PCAP_PACKET_COUNT=$(tshark -r "$OUTPUT_PCAP" 2>/dev/null | wc -l)
        
        # Check protocols present (sampling first 100 packets usually enough, but we'll check all unique)
        # We look specifically for DNS and HTTP
        HAS_DNS=$(tshark -r "$OUTPUT_PCAP" -Y "dns" -c 1 2>/dev/null | wc -l)
        HAS_HTTP=$(tshark -r "$OUTPUT_PCAP" -Y "http" -c 1 2>/dev/null | wc -l)
        
        PROTO_LIST=""
        if [ "$HAS_DNS" -gt 0 ]; then PROTO_LIST="${PROTO_LIST}DNS,"; fi
        if [ "$HAS_HTTP" -gt 0 ]; then PROTO_LIST="${PROTO_LIST}HTTP,"; fi
        PCAP_PROTOCOLS="$PROTO_LIST"

        # Check chronological order
        # We check if frame.time_epoch is strictly non-decreasing
        # capinfos -o gives strict order status
        ORDER_CHECK=$(capinfos -o "$OUTPUT_PCAP" 2>/dev/null | grep "Strict time order" | grep "True" || echo "False")
        if [[ "$ORDER_CHECK" == *"True"* ]]; then
            IS_CHRONOLOGICAL="true"
        fi
    fi
fi

# --- Analyze the Text Report ---
REPORT_EXISTS="false"
REPORT_CONTENT=""
REPORT_TOTAL_PACKETS=""
REPORT_PROTOCOLS=""

if [ -f "$OUTPUT_REPORT" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$OUTPUT_REPORT" | base64 -w 0) # Base64 encode for safe JSON
    
    # Extract values using grep/awk
    # "Total Packets: 81" -> 81
    REPORT_TOTAL_PACKETS=$(grep -i "Total Packets" "$OUTPUT_REPORT" | grep -o "[0-9]*" | head -1 || echo "")
    
    # "Protocols: DNS, HTTP" -> DNS, HTTP
    REPORT_PROTOCOLS=$(grep -i "Protocols" "$OUTPUT_REPORT" | cut -d: -f2- || echo "")
fi

# --- Gather Ground Truth ---
GT_CONTENT="{}"
if [ -f "$GROUND_TRUTH_FILE" ]; then
    GT_CONTENT=$(cat "$GROUND_TRUTH_FILE")
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# --- Create Result JSON ---
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "ground_truth": $GT_CONTENT,
    "pcap_analysis": {
        "exists": $PCAP_EXISTS,
        "valid": $PCAP_VALID,
        "created_during_task": $FILE_CREATED_DURING_TASK,
        "packet_count": $PCAP_PACKET_COUNT,
        "protocols_found": "$PCAP_PROTOCOLS",
        "is_chronological": $IS_CHRONOLOGICAL
    },
    "report_analysis": {
        "exists": $REPORT_EXISTS,
        "content_base64": "$REPORT_CONTENT",
        "extracted_count": "$REPORT_TOTAL_PACKETS",
        "extracted_protocols": "$REPORT_PROTOCOLS"
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="