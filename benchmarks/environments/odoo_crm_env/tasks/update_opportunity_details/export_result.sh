#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting task results ==="

LEAD_ID=$(cat /tmp/task_lead_id.txt 2>/dev/null || echo "")
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

if [ -z "$LEAD_ID" ]; then
    echo "ERROR: Could not find lead ID from setup"
    # Create empty error result
    cat > /tmp/task_result.json << EOF
{
    "error": "setup_failed_no_lead_id",
    "task_start": $TASK_START,
    "task_end": $TASK_END
}
EOF
    exit 0
fi

echo "Querying opportunity ID: $LEAD_ID"

# Query current values from database via XML-RPC
python3 << PYEOF
import xmlrpc.client
import json
import sys
import datetime

url = "http://localhost:8069"
db = "odoodb"
user = "admin"
passwd = "admin"

try:
    common = xmlrpc.client.ServerProxy(f"{url}/xmlrpc/2/common")
    uid = common.authenticate(db, user, passwd, {})
    
    models = xmlrpc.client.ServerProxy(f"{url}/xmlrpc/2/object")
    
    # Read the opportunity
    records = models.execute_kw(db, uid, passwd, 'crm.lead', 'read',
        [[${LEAD_ID}]], {'fields': ['name', 'expected_revenue', 'probability', 'priority', 'tag_ids', 'write_date']})
    
    if not records:
        result = {"error": "record_not_found"}
    else:
        record = records[0]
        
        # Get tag names
        tag_names = []
        if record.get('tag_ids'):
            tags = models.execute_kw(db, uid, passwd, 'crm.tag', 'read',
                [record['tag_ids']], {'fields': ['name']})
            tag_names = [t['name'] for t in tags]
        
        # Handle write_date timestamp
        write_date_str = record.get('write_date', '')
        write_ts = 0
        if write_date_str:
            try:
                # Odoo returns UTC usually
                dt = datetime.datetime.strptime(write_date_str, '%Y-%m-%d %H:%M:%S')
                # Simple approximation for timestamp comparison
                write_ts = int(dt.timestamp())
            except:
                pass

        result = {
            "lead_id": ${LEAD_ID},
            "name": record['name'],
            "expected_revenue": record['expected_revenue'],
            "probability": record['probability'],
            "priority": record['priority'],
            "tag_names": tag_names,
            "write_date": write_date_str,
            "write_timestamp": write_ts,
            "task_start": ${TASK_START},
            "task_end": ${TASK_END}
        }

    # Write to temp file first
    with open('/tmp/result_temp.json', 'w') as f:
        json.dump(result, f, indent=2)

except Exception as e:
    with open('/tmp/result_temp.json', 'w') as f:
        json.dump({"error": str(e)}, f)
PYEOF

# Move to final location safely
mv /tmp/result_temp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

# Take final screenshot
take_screenshot /tmp/task_final.png

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="