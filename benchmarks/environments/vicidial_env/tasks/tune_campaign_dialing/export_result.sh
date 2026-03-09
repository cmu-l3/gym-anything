#!/bin/bash
set -e
echo "=== Exporting Tune Campaign Dialing results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Query Database for Campaign Settings
echo "Querying campaign settings..."
CAMPAIGN_DATA=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -B -e "
    SELECT dial_statuses, lead_filter_id, dial_timeout, adaptive_dropped_percentage 
    FROM vicidial_campaigns 
    WHERE campaign_id='NURTURE'
")

# 3. Query Database for Filter Definition
echo "Querying filter definition..."
FILTER_SQL=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -B -e "
    SELECT lead_filter_sql 
    FROM vicidial_lead_filters 
    WHERE lead_filter_id='MAX_5_TRIES'
" 2>/dev/null || echo "")

# 4. Parse DB output
# CAMPAIGN_DATA format: " NEW BUSY N \t MAX_5_TRIES \t 45 \t 2"
# Use python to safely construct JSON to handle potential whitespace issues
python3 -c "
import json
import sys

try:
    camp_data = '''$CAMPAIGN_DATA'''.strip().split('\t')
    filter_sql = '''$FILTER_SQL'''.strip()
    
    if len(camp_data) >= 4:
        result = {
            'dial_statuses': camp_data[0].strip(),
            'lead_filter_id': camp_data[1].strip(),
            'dial_timeout': camp_data[2].strip(),
            'adaptive_dropped_percentage': camp_data[3].strip(),
            'filter_sql_content': filter_sql,
            'campaign_exists': True
        }
    else:
        result = {
            'campaign_exists': False,
            'error': 'Could not retrieve campaign data'
        }
except Exception as e:
    result = {'error': str(e), 'campaign_exists': False}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
"

# 5. Permission fix for copy_from_env
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="
cat /tmp/task_result.json