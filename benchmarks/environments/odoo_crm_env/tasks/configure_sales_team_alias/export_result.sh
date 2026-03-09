#!/bin/bash
echo "=== Exporting Configure Sales Team Alias Result ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Extract Sales Team data using Python/XML-RPC
# We use Python here because alias fields might be delegated or handled via mixins,
# and the ORM handles this cleaner than raw SQL.
python3 - <<PYEOF > /tmp/team_data.json
import xmlrpc.client
import json
import sys

result = {
    "team_found": False,
    "team_name": None,
    "alias_name": None,
    "alias_contact": None, # 'everyone', 'partners', 'followers'
    "user_id": None,
    "leader_name": None,
    "create_date": None
}

try:
    common = xmlrpc.client.ServerProxy('http://localhost:8069/xmlrpc/2/common')
    uid = common.authenticate('odoodb', 'admin', 'admin', {})
    models = xmlrpc.client.ServerProxy('http://localhost:8069/xmlrpc/2/object')

    # Search for the team
    team_ids = models.execute_kw('odoodb', uid, 'admin', 'crm.team', 'search',
        [[['name', '=', 'Direct Sales']]])
    
    if team_ids:
        # Read fields. Note: 'alias_name' and 'alias_contact' are usually available on crm.team 
        # due to inheritance from mail.alias.mixin
        fields = ['name', 'alias_name', 'alias_contact', 'user_id', 'create_date']
        team_data = models.execute_kw('odoodb', uid, 'admin', 'crm.team', 'read',
            [team_ids, fields])[0]
            
        result["team_found"] = True
        result["team_name"] = team_data.get('name')
        result["alias_name"] = team_data.get('alias_name')
        result["alias_contact"] = team_data.get('alias_contact')
        result["create_date"] = team_data.get('create_date')
        
        # user_id is returned as (id, name) tuple
        user_field = team_data.get('user_id')
        if user_field:
            result["user_id"] = user_field[0]
            result["leader_name"] = user_field[1]

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

# Combine into final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 - <<PYEOF > "$TEMP_JSON"
import json
import time

# Load python extraction result
try:
    with open('/tmp/team_data.json', 'r') as f:
        data = json.load(f)
except:
    data = {"team_found": False}

# Add system info
data['task_start'] = $TASK_START
data['task_end'] = $TASK_END
data['screenshot_path'] = "/tmp/task_final.png"

print(json.dumps(data, indent=2))
PYEOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON" /tmp/team_data.json

echo "Export complete. Result:"
cat /tmp/task_result.json