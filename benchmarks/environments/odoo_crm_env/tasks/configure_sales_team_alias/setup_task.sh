#!/bin/bash
set -e
echo "=== Setting up Configure Sales Team Alias Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Wait for Odoo to be ready
wait_for_odoo

# Clean up: Delete the target team if it already exists to ensure fresh creation
echo "Cleaning up any existing 'Direct Sales' team..."
python3 - <<'PYEOF'
import xmlrpc.client
import sys

try:
    common = xmlrpc.client.ServerProxy('http://localhost:8069/xmlrpc/2/common')
    uid = common.authenticate('odoodb', 'admin', 'admin', {})
    models = xmlrpc.client.ServerProxy('http://localhost:8069/xmlrpc/2/object')

    # Find existing team
    team_ids = models.execute_kw('odoodb', uid, 'admin', 'crm.team', 'search',
        [[['name', '=', 'Direct Sales']]])
    
    if team_ids:
        print(f"Found {len(team_ids)} existing team(s). Deleting...")
        models.execute_kw('odoodb', uid, 'admin', 'crm.team', 'unlink', [team_ids])
        print("Cleanup successful.")
    else:
        print("No existing team found. Clean state.")

except Exception as e:
    print(f"Error during cleanup: {e}", file=sys.stderr)
PYEOF

# Record initial count of sales teams
INITIAL_COUNT=$(docker exec odoo-db psql -U odoo -d odoodb -t -A -c "SELECT count(*) FROM crm_team" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_team_count.txt

# Ensure Firefox is running and logged in to the CRM Pipeline
# This puts the agent in the right app but requires them to find Configuration
ensure_odoo_logged_in "http://localhost:8069/web#action=209&model=crm.lead&view_type=kanban&cids=1&menu_id=139"

# Take screenshot of initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="