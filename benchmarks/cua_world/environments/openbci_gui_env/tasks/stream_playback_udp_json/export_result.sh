#!/bin/bash
echo "=== Exporting stream_playback_udp_json result ==="

source /home/ga/openbci_task_utils.sh || true

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Stop the UDP listener and OpenBCI GUI
pkill -f "udp_listener.py" || true
pkill -f "OpenBCI_GUI" || true

# 3. Analyze UDP Logs
LOG_FILE="/tmp/udp_stream_log.jsonl"
PACKET_COUNT=0
VALID_JSON_COUNT=0
HAS_EEG_DATA="false"

if [ -f "$LOG_FILE" ]; then
    PACKET_COUNT=$(wc -l < "$LOG_FILE")
    
    # Check for valid JSON entries
    VALID_JSON_COUNT=$(grep -c '"is_json": true' "$LOG_FILE" || echo "0")
    
    # Check for non-zero data in JSON content
    # Look for "data" array with non-zero values or "sampleNumber" changing
    # Typical OpenBCI JSON: {"type":"eeg", "data":[...], "sampleNumber": 123}
    if python3 -c "
import json
import sys

has_data = False
try:
    with open('$LOG_FILE', 'r') as f:
        for line in f:
            entry = json.loads(line)
            if entry.get('is_json') and entry.get('content'):
                c = entry['content']
                # Check for EEG data structure
                if 'data' in c and isinstance(c['data'], list):
                    # Check if any channel has non-zero data (avoiding 0.0 placeholders)
                    if any(abs(float(x)) > 0.0001 for x in c['data']):
                        has_data = True
                        break
                # Alternative format check
                if 'channel_data' in c:
                    if any(abs(float(x)) > 0.0001 for x in c['channel_data']):
                        has_data = True
                        break
    print('true' if has_data else 'false')
except Exception as e:
    print('false')
" | grep -q "true"; then
        HAS_EEG_DATA="true"
    fi
else
    echo "No UDP log file found."
fi

# 4. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "packet_count": $PACKET_COUNT,
    "valid_json_count": $VALID_JSON_COUNT,
    "has_eeg_data": $HAS_EEG_DATA,
    "timestamp": "$(date -Iseconds)",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported: $(cat /tmp/task_result.json)"