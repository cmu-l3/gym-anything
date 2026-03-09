#!/bin/bash
set -e

echo "=== Exporting AC-CID Task Results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query Database for Results using Docker Exec
# We need to extract:
# 1. The list of AC-CID entries for NEASTPRS
# 2. The 'areacode_cid' setting for NEASTPRS

echo "Querying Vicidial Database..."

# Get AC-CID entries as JSON-like string or CSV
# format: areacode,outbound_cid
ENTRIES_CSV=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e "
SELECT areacode, outbound_cid 
FROM vicidial_campaign_cid_areacodes 
WHERE campaign_id='NEASTPRS' 
ORDER BY areacode;
" 2>/dev/null || true)

# Get Campaign Setting
CAMPAIGN_SETTING=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e "
SELECT areacode_cid 
FROM vicidial_campaigns 
WHERE campaign_id='NEASTPRS';
" 2>/dev/null || echo "N")

# Process entries into JSON array
# Example CSV output:
# 203	2035559906
# 212	2125559901
ENTRIES_JSON="[]"
if [ -n "$ENTRIES_CSV" ]; then
    # Convert tab-separated DB output to JSON objects
    # This python snippet runs on the host to format the string from bash variable
    ENTRIES_JSON=$(python3 -c "
import sys, json
lines = sys.argv[1].strip().split('\n')
entries = []
for line in lines:
    if line.strip():
        parts = line.split('\t')
        if len(parts) >= 2:
            entries.append({'areacode': parts[0].strip(), 'cid': parts[1].strip()})
print(json.dumps(entries))
" "$ENTRIES_CSV")
fi

# Get initial count for anti-gaming
INITIAL_COUNT=$(cat /tmp/initial_accid_count.txt 2>/dev/null || echo "0")

# Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_count": $INITIAL_COUNT,
    "final_entries": $ENTRIES_JSON,
    "campaign_setting_enabled": "$CAMPAIGN_SETTING",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="