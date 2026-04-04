#!/bin/bash
set -e
echo "=== Exporting live DNS capture results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Load start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# --- 1. Locate and Validate Capture File ---
CAPTURES_DIR="/home/ga/Documents/captures"
PCAP_FILE=""
FILE_TYPE=""

if [ -s "$CAPTURES_DIR/live_dns_capture.pcapng" ]; then
    PCAP_FILE="$CAPTURES_DIR/live_dns_capture.pcapng"
    FILE_TYPE="pcapng"
elif [ -s "$CAPTURES_DIR/live_dns_capture.pcap" ]; then
    PCAP_FILE="$CAPTURES_DIR/live_dns_capture.pcap"
    FILE_TYPE="pcap"
fi

CAPTURE_EXISTS="false"
CAPTURE_VALID="false"
CAPTURE_MTIME=0
DNS_PACKET_COUNT=0
DOMAINS_FOUND_COUNT=0
FOUND_DOMAINS=""
CAPTURED_IPS=""

if [ -n "$PCAP_FILE" ]; then
    CAPTURE_EXISTS="true"
    CAPTURE_MTIME=$(stat -c %Y "$PCAP_FILE" 2>/dev/null || echo "0")
    
    # Validate with tshark
    if tshark -r "$PCAP_FILE" -c 1 > /dev/null 2>&1; then
        CAPTURE_VALID="true"
        
        # Analyze content
        DNS_PACKET_COUNT=$(tshark -r "$PCAP_FILE" -Y "dns" 2>/dev/null | wc -l)
        
        # Check specific domains
        for domain in example.com example.org example.net; do
            COUNT=$(tshark -r "$PCAP_FILE" -Y "dns.qry.name == \"$domain\"" 2>/dev/null | wc -l)
            if [ "$COUNT" -gt 0 ]; then
                DOMAINS_FOUND_COUNT=$((DOMAINS_FOUND_COUNT + 1))
                FOUND_DOMAINS="$FOUND_DOMAINS $domain"
                
                # Extract IPs for this domain to verify report later
                IPS=$(tshark -r "$PCAP_FILE" -Y "dns.qry.name == \"$domain\" && dns.a" -T fields -e dns.a 2>/dev/null | tr ',' '\n' | sort -u | tr '\n' ' ')
                if [ -n "$IPS" ]; then
                    CAPTURED_IPS="$CAPTURED_IPS|$domain:$IPS"
                fi
            fi
        done
    fi
fi

# --- 2. Locate and Validate Report File ---
REPORT_FILE="$CAPTURES_DIR/dns_analysis_report.txt"
REPORT_EXISTS="false"
REPORT_CONTENT=""
REPORT_MTIME=0

if [ -s "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    # Read content, limit size
    REPORT_CONTENT=$(cat "$REPORT_FILE" | head -c 2048)
fi

# --- 3. Generate Result JSON ---
# We use python3 to generate proper JSON to avoid shell escaping hell
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

python3 -c "
import json
import sys

data = {
    'task_start_time': int(sys.argv[1]),
    'capture': {
        'exists': sys.argv[2] == 'true',
        'valid': sys.argv[3] == 'true',
        'mtime': int(sys.argv[4]),
        'filename': sys.argv[5],
        'dns_packet_count': int(sys.argv[6]),
        'domains_found_count': int(sys.argv[7]),
        'found_domains': sys.argv[8].strip().split(),
        'captured_ips_raw': sys.argv[9]
    },
    'report': {
        'exists': sys.argv[10] == 'true',
        'mtime': int(sys.argv[11]),
        'content': sys.argv[12]
    },
    'screenshot_path': '/tmp/task_final.png'
}

with open(sys.argv[13], 'w') as f:
    json.dump(data, f, indent=4)
" \
"$TASK_START" \
"$CAPTURE_EXISTS" \
"$CAPTURE_VALID" \
"$CAPTURE_MTIME" \
"$(basename "$PCAP_FILE")" \
"$DNS_PACKET_COUNT" \
"$DOMAINS_FOUND_COUNT" \
"$FOUND_DOMAINS" \
"$CAPTURED_IPS" \
"$REPORT_EXISTS" \
"$REPORT_MTIME" \
"$REPORT_CONTENT" \
"$TEMP_JSON"

# Safely move JSON to standard location
safe_json_write "$(cat "$TEMP_JSON")" "/tmp/task_result.json"
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="