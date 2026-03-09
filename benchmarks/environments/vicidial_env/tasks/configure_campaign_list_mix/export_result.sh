#!/bin/bash
echo "=== Exporting List Mix Configuration Results ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# capture final screenshot
take_screenshot /tmp/task_final.png

# Query Database for Final State
# We need to check:
# 1. Did the List Mix 'REGIONAL_BLEND' get created?
# 2. Does it have the correct entries (list_id -> percentage)?
# 3. Is the campaign 'SENMIX' configured to use it?

echo "Querying Vicidial Database..."

# Get List Mix Definition
# Table: vicidial_campaigns_list_mix (vcl_id, vcl_name, campaign_id, status, ...)
MIX_EXISTS_JSON=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -e "
SELECT vcl_id, campaign_id, status, modify_date 
FROM vicidial_campaigns_list_mix 
WHERE vcl_id='REGIONAL_BLEND' 
LIMIT 1 \G" | \
python3 -c '
import sys, json
lines = sys.stdin.readlines()
data = {}
for line in lines:
    if ":" in line:
        key, val = line.split(":", 1)
        data[key.strip()] = val.strip()
print(json.dumps(data))
')

# Get List Mix Entries
# Table: vicidial_campaigns_list_mix_entry (vcl_id, list_id, percentage, ...)
MIX_ENTRIES_JSON=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e "
SELECT list_id, percentage 
FROM vicidial_campaigns_list_mix_entry 
WHERE vcl_id='REGIONAL_BLEND';" | \
python3 -c '
import sys, json
entries = {}
for line in sys.stdin:
    parts = line.strip().split()
    if len(parts) >= 2:
        entries[parts[0]] = parts[1]
print(json.dumps(entries))
')

# Get Campaign Configuration
# Check if dial_method is set to proper mix method OR if list_order_mix is set
# Note: In some Vicidial versions, enabling list mix changes dial_method to "LMIX" or similar, 
# or it uses a specific hopper loading method. We will check relevant fields.
CAMPAIGN_CONFIG_JSON=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -e "
SELECT campaign_id, dial_method, list_order_mix, list_order_random 
FROM vicidial_campaigns 
WHERE campaign_id='SENMIX' \G" | \
python3 -c '
import sys, json
lines = sys.stdin.readlines()
data = {}
for line in lines:
    if ":" in line:
        key, val = line.split(":", 1)
        data[key.strip()] = val.strip()
print(json.dumps(data))
')

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "mix_exists_data": $MIX_EXISTS_JSON,
    "mix_entries": $MIX_ENTRIES_JSON,
    "campaign_config": $CAMPAIGN_CONFIG_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Safe move
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="