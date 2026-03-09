#!/bin/bash
set -e

echo "=== Exporting filter_http_traffic result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Gather verification data
INITIAL_TOTAL=$(cat /tmp/initial_total_packets 2>/dev/null || echo "0")
INITIAL_HTTP=$(cat /tmp/initial_http_packets 2>/dev/null || echo "0")

# Check if filtered output file was created
FILTERED_FILE="/home/ga/Documents/captures/filtered_http.pcap"
FILTERED_EXISTS="false"
FILTERED_PACKETS=0
ALL_HTTP="false"

HTTP_PACKETS_IN_FILE=0

if [ -s "$FILTERED_FILE" ]; then
    FILTERED_EXISTS="true"
    FILTERED_PACKETS=$(tshark -r "$FILTERED_FILE" 2>/dev/null | wc -l)

    if [ "$FILTERED_PACKETS" -gt 0 ]; then
        HTTP_PACKETS_IN_FILE=$(tshark -r "$FILTERED_FILE" -Y "http" 2>/dev/null | wc -l)

        NON_HTTP=$(tshark -r "$FILTERED_FILE" -Y "!http" 2>/dev/null | wc -l)
        if [ "$NON_HTTP" -eq 0 ] && [ "$FILTERED_PACKETS" -gt 0 ]; then
            ALL_HTTP="true"
        fi

        NON_HTTP_TCP=$(tshark -r "$FILTERED_FILE" -Y "!http and !tcp" 2>/dev/null | wc -l)
        if [ "$NON_HTTP_TCP" -eq 0 ] && [ "$HTTP_PACKETS_IN_FILE" -gt 0 ]; then
            ALL_HTTP="true"
        fi
    fi
fi

# Check if Wireshark is still running
WIRESHARK_RUNNING=$(is_wireshark_running)

# Check for alternative output locations
ALT_FILES=""
for alt in /home/ga/Desktop/filtered_http.pcap /home/ga/filtered_http.pcap /tmp/filtered_http.pcap /home/ga/Documents/filtered_http.pcap; do
    if [ -s "$alt" ]; then
        ALT_FILES="$ALT_FILES $alt"
        if [ "$FILTERED_EXISTS" = "false" ]; then
            FILTERED_EXISTS="true"
            FILTERED_FILE="$alt"
            FILTERED_PACKETS=$(tshark -r "$alt" 2>/dev/null | wc -l)
            if [ "$FILTERED_PACKETS" -gt 0 ]; then
                HTTP_PACKETS_IN_FILE=$(tshark -r "$alt" -Y "http" 2>/dev/null | wc -l)
                NON_HTTP=$(tshark -r "$alt" -Y "!http" 2>/dev/null | wc -l)
                if [ "$NON_HTTP" -eq 0 ] && [ "$FILTERED_PACKETS" -gt 0 ]; then
                    ALL_HTTP="true"
                fi
                NON_HTTP_TCP=$(tshark -r "$alt" -Y "!http and !tcp" 2>/dev/null | wc -l)
                if [ "$NON_HTTP_TCP" -eq 0 ] && [ "$HTTP_PACKETS_IN_FILE" -gt 0 ]; then
                    ALL_HTTP="true"
                fi
            fi
        fi
    fi
done

# Create result JSON safely using python3
WS_RUNNING=$([ "$WIRESHARK_RUNNING" -gt 0 ] && echo "true" || echo "false")
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 -c "
import json, sys
data = {
    'initial_total_packets': int(sys.argv[1]) if sys.argv[1].isdigit() else 0,
    'initial_http_packets': int(sys.argv[2]) if sys.argv[2].isdigit() else 0,
    'filtered_file_exists': sys.argv[3] == 'true',
    'filtered_file_path': sys.argv[4],
    'filtered_packet_count': int(sys.argv[5]) if sys.argv[5].isdigit() else 0,
    'http_packets_in_file': int(sys.argv[6]) if sys.argv[6].isdigit() else 0,
    'all_packets_are_http': sys.argv[7] == 'true',
    'wireshark_running': sys.argv[8] == 'true',
    'alternative_files': sys.argv[9].strip(),
    'timestamp': sys.argv[10]
}
with open(sys.argv[11], 'w') as f:
    json.dump(data, f, indent=4)
" "$INITIAL_TOTAL" "$INITIAL_HTTP" "$FILTERED_EXISTS" "$FILTERED_FILE" "$FILTERED_PACKETS" "$HTTP_PACKETS_IN_FILE" "$ALL_HTTP" "$WS_RUNNING" "$ALT_FILES" "$(date -Iseconds)" "$TEMP_JSON"

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
