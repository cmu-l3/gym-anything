#!/bin/bash
echo "=== Setting up fold_done_alert_stage task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Wait for Odoo to be ready
echo "Waiting for Odoo..."
for i in {1..30}; do
    if curl -s "http://localhost:8069/web/health" | grep -q "200" || \
       curl -s -o /dev/null -w "%{http_code}" "http://localhost:8069" | grep -q "200" || \
       curl -s -o /dev/null -w "%{http_code}" "http://localhost:8069/web/login" | grep -q "200"; then
        echo "Odoo is responsive."
        break
    fi
    sleep 2
done

# Prepare Data: Ensure "Done" stage exists and is currently Unfolded (False)
echo "Configuring initial stage state via XML-RPC..."
python3 << 'PYTHON_EOF'
import xmlrpc.client
import sys
import time

url = "http://localhost:8069"
db = "odoo_quality"
username = "admin"
password = "admin"

try:
    # Connect
    common = xmlrpc.client.ServerProxy(f"{url}/xmlrpc/2/common")
    uid = common.authenticate(db, username, password, {})
    if not uid:
        print("Authentication failed")
        sys.exit(1)
    
    models = xmlrpc.client.ServerProxy(f"{url}/xmlrpc/2/object")

    # Search for "Done" stage
    stage_ids = models.execute_kw(db, uid, password, 'quality.alert.stage', 'search', 
        [[['name', '=', 'Done']]])

    if not stage_ids:
        # Create it if missing
        stage_id = models.execute_kw(db, uid, password, 'quality.alert.stage', 'create', 
            [{'name': 'Done', 'fold': False, 'sequence': 100}])
        print(f"Created 'Done' stage (id={stage_id})")
    else:
        stage_id = stage_ids[0]
        # Force it to be UNFOLDED (fold=False) so the task is meaningful
        models.execute_kw(db, uid, password, 'quality.alert.stage', 'write', 
            [[stage_id], {'fold': False}])
        print(f"Reset 'Done' stage (id={stage_id}) to fold=False")

    # Record the ID for verification later
    with open("/tmp/target_stage_id.txt", "w") as f:
        f.write(str(stage_id))

except Exception as e:
    print(f"Error in setup: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF

# Ensure Firefox is running and logged in
ensure_firefox "http://localhost:8069/web"

# Take initial screenshot
echo "Capturing initial state..."
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="