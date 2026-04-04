#!/bin/bash
set -e
echo "=== Exporting Configure Group Alias Result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Query Database for Group Alias 'RETENTION_HQ'
echo "Querying Group Alias..."
ALIAS_JSON=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e \
"SELECT JSON_OBJECT(
    'group_alias_id', group_alias_id, 
    'group_alias_name', group_alias_name, 
    'caller_id_number', caller_id_number, 
    'caller_id_name', caller_id_name, 
    'active', active
) 
FROM vicidial_group_aliases 
WHERE group_alias_id='RETENTION_HQ';" 2>/dev/null || echo "")

if [ -z "$ALIAS_JSON" ]; then
    ALIAS_JSON="null"
fi

# 3. Query Database for Campaign 'RETENTION' setting
echo "Querying Campaign Setting..."
CAMPAIGN_JSON=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e \
"SELECT JSON_OBJECT(
    'campaign_id', campaign_id, 
    'default_group_alias', default_group_alias
) 
FROM vicidial_campaigns 
WHERE campaign_id='RETENTION';" 2>/dev/null || echo "")

if [ -z "$CAMPAIGN_JSON" ]; then
    CAMPAIGN_JSON="null"
fi

# 4. Get Counts and Timestamps
INITIAL_COUNT=$(cat /tmp/initial_alias_count.txt 2>/dev/null || echo "0")
FINAL_COUNT=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e "SELECT count(*) FROM vicidial_group_aliases;" 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 5. Construct Final JSON
# Use a python script to safely merge JSON objects
python3 -c "
import json
import time

try:
    alias_data = $ALIAS_JSON if '$ALIAS_JSON' != 'null' else None
    campaign_data = $CAMPAIGN_JSON if '$CAMPAIGN_JSON' != 'null' else None
    
    result = {
        'alias_found': alias_data is not None,
        'alias_data': alias_data,
        'campaign_found': campaign_data is not None,
        'campaign_data': campaign_data,
        'initial_count': int('$INITIAL_COUNT'),
        'final_count': int('$FINAL_COUNT'),
        'task_start_ts': int('$TASK_START'),
        'export_ts': int(time.time()),
        'screenshot_path': '/tmp/task_final.png'
    }
    
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f, indent=2)
except Exception as e:
    print(f'Error creating JSON: {e}')
    # Fallback JSON
    with open('/tmp/task_result.json', 'w') as f:
        json.dump({'error': str(e)}, f)
"

# Set permissions so the host can read it via copy_from_env
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="