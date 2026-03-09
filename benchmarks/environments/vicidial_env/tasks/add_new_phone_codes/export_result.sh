#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Query Database for Phone Codes
# We select the specific codes we asked the agent to create
# Output format: tab-separated
echo "Querying database for phone codes..."
DB_OUTPUT=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -B -e \
    "SELECT country_code, areacode, GMT_offset, DST, state, geographic_description 
     FROM vicidial_phone_codes 
     WHERE areacode IN ('324', '729', '839') 
     ORDER BY areacode;")

# 2. Query Admin Log for Anti-Gaming
# Check if these codes were added via the web interface (event_type='ADD', event_section='PHONECODES')
# filtering by time > TASK_START
echo "Querying admin log..."
LOG_OUTPUT=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -B -e \
    "SELECT count(*) FROM vicidial_admin_log 
     WHERE event_section='PHONECODES' 
     AND event_type='ADD' 
     AND record_id IN ('324', '729', '839') 
     AND event_time > FROM_UNIXTIME($TASK_START);")

# 3. Take final screenshot
take_screenshot /tmp/task_final.png

# 4. Construct JSON Result using Python for safety
# We pass the raw DB output to Python to parse into JSON
python3 -c "
import json
import sys
import time

try:
    task_start = $TASK_START
    task_end = $TASK_END
    
    # Parse DB Output
    # Expected format: 1	324	-5.00	Y	FL	Jacksonville Overlay
    db_raw = '''$DB_OUTPUT'''
    records = {}
    for line in db_raw.strip().split('\n'):
        parts = line.split('\t')
        if len(parts) >= 6:
            records[parts[1]] = {
                'cc': parts[0],
                'gmt': parts[2],
                'dst': parts[3],
                'state': parts[4],
                'desc': parts[5]
            }
            
    # Parse Log Output
    log_count = int('''$LOG_OUTPUT'''.strip() or '0')
    
    result = {
        'task_start': task_start,
        'task_end': task_end,
        'records': records,
        'admin_log_add_count': log_count,
        'screenshot_path': '/tmp/task_final.png'
    }
    
    print(json.dumps(result, indent=2))
    
except Exception as e:
    print(json.dumps({'error': str(e)}))

" > /tmp/task_result.json

# Move to final location with permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="