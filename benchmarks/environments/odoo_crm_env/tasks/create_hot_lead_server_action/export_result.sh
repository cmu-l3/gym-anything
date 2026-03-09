#!/bin/bash
echo "=== Exporting create_hot_lead_server_action result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Get Task Start Time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Collect verification data via Python/XML-RPC
python3 - <<PYEOF
import xmlrpc.client
import json
import datetime

def serialize(obj):
    if isinstance(obj, (datetime.date, datetime.datetime)):
        return obj.isoformat()
    return obj

result = {
    "task_start_timestamp": int("$TASK_START"),
    "server_action": None,
    "action_lines": [],
    "opportunity": None
}

try:
    common = xmlrpc.client.ServerProxy('http://localhost:8069/xmlrpc/2/common')
    uid = common.authenticate('odoodb', 'admin', 'admin', {})
    models = xmlrpc.client.ServerProxy('http://localhost:8069/xmlrpc/2/object')

    # 1. Check for the Server Action
    action_ids = models.execute_kw('odoodb', uid, 'admin', 'ir.actions.server', 'search',
        [[['name', '=', 'Mark as Hot Lead']]])
    
    if action_ids:
        # Get the most recently created one if multiple
        action_data = models.execute_kw('odoodb', uid, 'admin', 'ir.actions.server', 'read',
            [action_ids], 
            {'fields': ['name', 'model_id', 'state', 'binding_model_id', 'create_date', 'child_ids']})
        
        # Sort by create_date desc
        action_data.sort(key=lambda x: x['create_date'], reverse=True)
        target_action = action_data[0]
        
        # Get model name from model_id (returns [id, name])
        model_name = target_action['model_id'][1] if target_action['model_id'] else ""
        
        result["server_action"] = {
            "exists": True,
            "name": target_action['name'],
            "model_name": model_name,
            "state": target_action['state'], # Should be 'object_write' for Update Record
            "is_bound": bool(target_action['binding_model_id']), # Contextual Action created?
            "create_date": target_action['create_date']
        }

        # 2. Check Action Lines (The actual updates configured)
        # In Odoo 17, 'Update Record' actions usually imply child lines or specific fields
        # Note: field names might differ slightly by version, checking generic 'ir.server.object.lines' or similar
        # For 'object_write', Odoo uses a separate model or field to store values.
        # Often it is related via 'link_field_id' or child lines. 
        # Let's try to fetch lines if they exist for this action type.
        
        # Fetch lines (fields to update)
        # Only applicable if state == 'object_write'
        # The model is usually ir.server.object.lines (depending on Odoo version, could be different)
        # Let's try to search for lines linked to this action.
        
        # IMPORTANT: In newer Odoo versions, for 'Update Record', the lines are often in 'update_path_ids' or similar.
        # But 'Update Record' type is 'object_write'.
        # Let's try checking 'update_m2m_ids' or similar if available, OR just trust the 'selection' and 'value' fields 
        # But typically it's a One2many. Let's try generic query on 'ir.server.object.lines'.
        
        lines = models.execute_kw('odoodb', uid, 'admin', 'ir.server.object.lines', 'search_read',
            [[['server_id', '=', target_action['id']]]],
            {'fields': ['col1', 'value']}) # col1 is usually the field_id
            
        # We need the field names for col1
        parsed_lines = []
        for line in lines:
            if line['col1']:
                field_info = models.execute_kw('odoodb', uid, 'admin', 'ir.model.fields', 'read',
                    [line['col1'][0]], {'fields': ['name']})
                field_name = field_info[0]['name']
                parsed_lines.append({'field': field_name, 'value': line['value']})
        
        result["action_lines"] = parsed_lines

    else:
        result["server_action"] = {"exists": False}

    # 3. Check the Opportunity State
    opp_name = "Solar Panel Upgrade - Smith Residence"
    opp_ids = models.execute_kw('odoodb', uid, 'admin', 'crm.lead', 'search',
        [[['name', '=', opp_name]]])
    
    if opp_ids:
        opp = models.execute_kw('odoodb', uid, 'admin', 'crm.lead', 'read',
            [opp_ids[0]], 
            {'fields': ['priority', 'probability', 'write_date']})
        result["opportunity"] = opp[0]

except Exception as e:
    result["error"] = str(e)

# Write to temp file with permissions
with open('/tmp/result_temp.json', 'w') as f:
    json.dump(result, f, default=serialize, indent=2)
PYEOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/result_temp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f /tmp/result_temp.json

echo "Export complete. Result preview:"
head -n 20 /tmp/task_result.json