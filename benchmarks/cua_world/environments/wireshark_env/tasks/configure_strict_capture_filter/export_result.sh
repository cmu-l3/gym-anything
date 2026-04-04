#!/bin/bash
set -e

echo "=== Exporting configure_strict_capture_filter result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Stop noise generators
if [ -f /tmp/noise_generator.pid ]; then
    kill $(cat /tmp/noise_generator.pid) 2>/dev/null || true
    rm /tmp/noise_generator.pid
fi
if [ -f /tmp/noise_http_server.pid ]; then
    kill $(cat /tmp/noise_http_server.pid) 2>/dev/null || true
    rm /tmp/noise_http_server.pid
fi
pkill -f "noise_generator.sh" 2>/dev/null || true

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)

# File paths
OUTPUT_FILE="/home/ga/Documents/captures/icmp_strict.pcapng"

# Initialize result variables
FILE_EXISTS="false"
FILE_SIZE="0"
TOTAL_PACKETS="0"
ICMP_PACKETS="0"
NON_ICMP_PACKETS="0"
FILE_CREATED_DURING_TASK="false"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Analyze output file
if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    # Check creation time
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Analyze packets with tshark
    # 1. Total valid packets
    TOTAL_PACKETS=$(tshark -r "$OUTPUT_FILE" 2>/dev/null | wc -l)
    
    # 2. ICMP packets (Goal)
    ICMP_PACKETS=$(tshark -r "$OUTPUT_FILE" -Y "icmp" 2>/dev/null | wc -l)
    
    # 3. Non-ICMP packets (Noise - MUST BE ZERO)
    # We explicitly exclude ICMP and ARP (sometimes users forget ARP, but task said ONLY ICMP)
    # The task says "ONLY ICMP traffic". Strict interpretation: ARP is not ICMP.
    NON_ICMP_PACKETS=$(tshark -r "$OUTPUT_FILE" -Y "not icmp" 2>/dev/null | wc -l)
    
    echo "Analysis: Total=$TOTAL_PACKETS, ICMP=$ICMP_PACKETS, Noise=$NON_ICMP_PACKETS"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size_bytes": $FILE_SIZE,
    "total_packets": $TOTAL_PACKETS,
    "icmp_packets": $ICMP_PACKETS,
    "non_icmp_packets": $NON_ICMP_PACKETS,
    "task_start_timestamp": $TASK_START,
    "export_timestamp": $CURRENT_TIME
}
EOF

# Save result with permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="