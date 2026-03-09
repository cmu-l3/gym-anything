#!/bin/bash
set -e
echo "=== Setting up edit_stage_probabilities task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
# Also in ISO format for easy reading
date -u +"%Y-%m-%d %H:%M:%S" > /tmp/task_start_iso.txt

# Wait for Odoo to be ready
wait_for_odoo

# Reset stages to known bad state (so we can verify the agent actually changed them)
# We use Python XMLRPC for this to ensure database consistency
python3 - <<'PYEOF'
import xmlrpc.client
import sys

try:
    common = xmlrpc.client.ServerProxy('http://localhost:8069/xmlrpc/2/common')
    uid = common.authenticate('odoodb', 'admin', 'admin', {})
    models = xmlrpc.client.ServerProxy('http://localhost:8069/xmlrpc/2/object')

    # Define initial incorrect states
    # Note: Odoo 17 might have different default stages, we ensure these 4 exist and are reset
    initial_states = {
        'New': {'probability': 10.0, 'requirements': False, 'sequence': 1},
        'Qualified': {'probability': 20.0, 'requirements': False, 'sequence': 2},
        'Proposition': {'probability': 50.0, 'requirements': False, 'sequence': 3},
        'Won': {'probability': 100.0, 'requirements': False, 'sequence': 4, 'is_won': True}
    }

    print("Resetting CRM stages...")
    
    for name, data in initial_states.items():
        # Search for stage
        domain = [['name', '=', name]]
        existing = models.execute_kw('odoodb', uid, 'admin', 'crm.stage', 'search', [domain])
        
        if existing:
            # Update existing
            models.execute_kw('odoodb', uid, 'admin', 'crm.stage', 'write', [existing, data])
            print(f"Reset stage '{name}' (ID: {existing[0]})")
        else:
            # Create if missing
            data['name'] = name
            new_id = models.execute_kw('odoodb', uid, 'admin', 'crm.stage', 'create', [data])
            print(f"Created stage '{name}' (ID: {new_id})")

    print("Stage reset complete.")

except Exception as e:
    print(f"Error resetting stages: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF

# Ensure Firefox is running and logged in
# Navigate to CRM Pipeline (action 209 is typical for CRM Pipeline)
CRM_URL="http://localhost:8069/web#action=209&model=crm.lead&view_type=kanban&cids=1&menu_id=139"
ensure_odoo_logged_in "$CRM_URL"

# Wait a moment for the Kanban view to load fully
sleep 5

# Take screenshot of initial state (showing the pipeline)
take_screenshot /tmp/task_initial.png
echo "Initial screenshot captured."

echo "=== Setup complete ==="