#!/bin/bash
echo "=== Exporting batch_tag_meetings_by_keyword result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Export data via Python/XML-RPC
# We need:
# 1. All events: Name, Description, Tag Names
# 2. Existence of "Audit" tag
# 3. Timestamps to verify work was done recently

python3 << 'PYTHON_EOF'
import xmlrpc.client, json, sys, os
from datetime import datetime

url = 'http://localhost:8069'
db = 'odoo_scheduling'
task_start_ts = 0

try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        task_start_ts = float(f.read().strip())
except:
    pass

output = {
    "task_start_ts": task_start_ts,
    "audit_tag_exists": False,
    "audit_tag_id": None,
    "events": []
}

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, 'admin', 'admin', {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # 1. Check if "Audit" tag exists
    tags = models.execute_kw(db, uid, 'admin', 'calendar.event.type', 'search_read',
                             [[['name', '=', 'Audit']]], {'fields': ['id', 'name']})
    if tags:
        output["audit_tag_exists"] = True
        output["audit_tag_id"] = tags[0]['id']

    # 2. Fetch all events
    # We fetch name, description, categ_ids (tags), and write_date
    events = models.execute_kw(db, uid, 'admin', 'calendar.event', 'search_read',
                               [[]], 
                               {'fields': ['name', 'description', 'categ_ids', 'write_date']})

    # For categ_ids, Odoo returns [id, name] list or just IDs depending on version/context.
    # search_read typically returns IDs for Many2many.
    # We need to resolve tag IDs to names to be sure.
    
    # Fetch all tags to map IDs to names
    all_tags = models.execute_kw(db, uid, 'admin', 'calendar.event.type', 'search_read',
                                 [[]], {'fields': ['id', 'name']})
    tag_map = {t['id']: t['name'] for t in all_tags}

    for ev in events:
        # Resolve tag names
        tag_ids = ev.get('categ_ids', [])
        tag_names = [tag_map.get(tid, str(tid)) for tid in tag_ids]
        
        # Convert write_date to timestamp for comparison
        write_date_str = ev.get('write_date', '')
        write_ts = 0
        if write_date_str:
            # Odoo dates are UTC string "YYYY-MM-DD HH:MM:SS"
            try:
                dt = datetime.strptime(write_date_str, "%Y-%m-%d %H:%M:%S")
                # Simple approximation or conversion logic needed? 
                # Assuming container timezone is UTC or close enough for delta checks
                # The task_start_time.txt is unix timestamp.
                # Let's just store the string and process in verifier or rough convert here.
                # Actually, Odoo 17 might return string. Let's send raw string and handle in verifier.
                pass
            except:
                pass

        output["events"].append({
            "id": ev['id'],
            "name": ev.get('name', ''),
            "description": ev.get('description', '') or "",
            "tags": tag_names,
            "write_date": write_date_str
        })

    # Save to JSON
    with open('/tmp/batch_tag_result.json', 'w') as f:
        json.dump(output, f, indent=2)

    print("Data exported successfully.")

except Exception as e:
    print(f"Error exporting data: {e}", file=sys.stderr)
    # Create empty/error result
    with open('/tmp/batch_tag_result.json', 'w') as f:
        json.dump({"error": str(e)}, f)
PYTHON_EOF

# Permission fix
chmod 666 /tmp/batch_tag_result.json 2>/dev/null || true

echo "=== Export complete ==="