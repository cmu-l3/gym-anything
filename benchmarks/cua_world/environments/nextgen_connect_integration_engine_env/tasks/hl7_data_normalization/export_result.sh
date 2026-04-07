#!/bin/bash
echo "=== Exporting HL7 Normalization Result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Take Evidence Screenshot
take_screenshot /tmp/task_final.png

# 2. Collect Channel Information
INITIAL_COUNT=$(cat /tmp/initial_channel_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(get_channel_count)
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Find the specific channel
CHANNEL_ID=$(get_channel_id "Data_Quality_Normalizer")
CHANNEL_STATUS="UNKNOWN"
STATS_RECEIVED=0

if [ -n "$CHANNEL_ID" ]; then
    CHANNEL_STATUS=$(get_channel_status_api "$CHANNEL_ID")
    
    # Get statistics
    STATS_JSON=$(get_channel_stats_api "$CHANNEL_ID")
    if [ -n "$STATS_JSON" ]; then
        STATS_RECEIVED=$(echo "$STATS_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('channelStatistics',{}).get('received',0))" 2>/dev/null || echo "0")
    fi
    
    # Get configuration (to check for transformers)
    CHANNEL_XML=$(query_postgres "SELECT channel FROM channel WHERE id='$CHANNEL_ID';" 2>/dev/null || true)
    HAS_TRANSFORMER=$(echo "$CHANNEL_XML" | grep -qi "transformer" && echo "true" || echo "false")
else
    HAS_TRANSFORMER="false"
fi

# 3. Process Output Files
# We need to read the content of the files to verify normalization
# The verifier runs on host, but files are in container/volume. 
# We'll parse them here into a JSON structure.

echo "Parsing output files..."
OUTPUT_FILES_JSON=$(python3 -c "
import os
import glob
import json
import re

output_dir = '/tmp/normalized_output'
results = []

if os.path.exists(output_dir):
    files = glob.glob(os.path.join(output_dir, '*.hl7'))
    for fpath in files:
        try:
            # Check modification time
            mtime = os.path.getmtime(fpath)
            
            with open(fpath, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
                
            # Parse HL7 manually (split by segment delimiter \r or \n)
            segments = re.split(r'[\r\n]+', content.strip())
            
            pid_data = {}
            msh_sender = ''
            
            for seg in segments:
                if seg.startswith('MSH|'):
                    fields = seg.split('|')
                    if len(fields) > 2:
                        msh_sender = fields[2]
                
                if seg.startswith('PID|'):
                    fields = seg.split('|')
                    # PID indices (1-based in spec, 0-based in python list)
                    # MSH is handled differently, but usually splitting string by | works for PID
                    # PID|1|...
                    # fields[0] = PID
                    # fields[7] = DOB (PID-7)
                    # fields[8] = Gender (PID-8)
                    # fields[13] = Phone Home (PID-13)
                    
                    if len(fields) > 7:
                        pid_data['dob'] = fields[7]
                    if len(fields) > 8:
                        pid_data['gender'] = fields[8]
                    if len(fields) > 13:
                        # Phone often has components ^^^
                        phone_field = fields[13]
                        pid_data['phone'] = phone_field.split('^')[0] if phone_field else ''

            results.append({
                'filename': os.path.basename(fpath),
                'mtime': mtime,
                'sender': msh_sender,
                'pid': pid_data
            })
        except Exception as e:
            results.append({'filename': os.path.basename(fpath), 'error': str(e)})

print(json.dumps(results))
" 2>/dev/null)

# 4. Create Result JSON
JSON_CONTENT=$(cat <<EOF
{
    "task_start": $TASK_START,
    "initial_channel_count": $INITIAL_COUNT,
    "current_channel_count": $CURRENT_COUNT,
    "channel_id": "$CHANNEL_ID",
    "channel_status": "$CHANNEL_STATUS",
    "stats_received": $STATS_RECEIVED,
    "has_transformer": $HAS_TRANSFORMER,
    "output_files": $OUTPUT_FILES_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF
)

write_result_json "/tmp/task_result.json" "$JSON_CONTENT"
echo "Export complete. Result saved to /tmp/task_result.json"