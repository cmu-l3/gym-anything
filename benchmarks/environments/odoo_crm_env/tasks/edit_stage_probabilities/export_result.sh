#!/bin/bash
echo "=== Exporting edit_stage_probabilities results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_START_ISO=$(cat /tmp/task_start_iso.txt 2>/dev/null || echo "1970-01-01 00:00:00")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Fetch current stage configuration from Odoo via XMLRPC
python3 - > /tmp/stages_export.json <<PYEOF
import xmlrpc.client
import json
import datetime

def json_serial(obj):
    if isinstance(obj, (datetime.date, datetime.datetime)):
        return obj.isoformat()
    return str(obj)

try:
    common = xmlrpc.client.ServerProxy('http://localhost:8069/xmlrpc/2/common')
    uid = common.authenticate('odoodb', 'admin', 'admin', {})
    models = xmlrpc.client.ServerProxy('http://localhost:8069/xmlrpc/2/object')

    # Fetch stages
    stage_names = ['New', 'Qualified', 'Proposition', 'Won']
    domain = [['name', 'in', stage_names]]
    fields = ['name', 'probability', 'requirements', 'write_date']
    
    stages = models.execute_kw('odoodb', uid, 'admin', 'crm.stage', 'search_read', [domain], {'fields': fields})
    
    result = {
        'stages': stages,
        'task_start_iso': '$TASK_START_ISO',
        'task_start_ts': $TASK_START,
        'task_end_ts': $TASK_END
    }
    
    print(json.dumps(result, default=json_serial))

except Exception as e:
    print(json.dumps({'error': str(e)}))
PYEOF

# Move result to final location with permissive permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/stages_export.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="