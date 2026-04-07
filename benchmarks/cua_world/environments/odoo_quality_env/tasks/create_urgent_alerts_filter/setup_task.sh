#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Setting up task: create_urgent_alerts_filter ==="

# Record start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Create dummy data and clean up existing filters
# We do this via Python inside the container to ensure DB consistency
python3 << 'PYTHON_EOF'
import xmlrpc.client
import sys
import time

url = "http://localhost:8069"
db = "odoo_quality"
password = "admin"

try:
    # Connect
    common = xmlrpc.client.ServerProxy(f"{url}/xmlrpc/2/common")
    uid = common.authenticate(db, "admin", password, {})
    models = xmlrpc.client.ServerProxy(f"{url}/xmlrpc/2/object")
    
    if not uid:
        print("Error: Authentication failed")
        sys.exit(1)

    print(f"Connected as uid={uid}")

    # 1. CLEANUP: Delete any existing 'Urgent Actions' filters to ensure freshness
    existing_filters = models.execute_kw(db, uid, password, 'ir.filters', 'search', 
        [[('name', 'ilike', 'Urgent Actions'), ('model_id', '=', 'quality.alert')]])
    
    if existing_filters:
        models.execute_kw(db, uid, password, 'ir.filters', 'unlink', [existing_filters])
        print(f"Cleaned up {len(existing_filters)} existing filters named 'Urgent Actions'")

    # 2. DATA PREP: Ensure we have 'New' and 'Done' stages
    stages = models.execute_kw(db, uid, password, 'quality.alert.stage', 'search_read', 
        [[]], {'fields': ['id', 'name']})
    
    new_stage_id = None
    done_stage_id = None
    
    for s in stages:
        name_lower = s['name'].lower()
        if 'new' in name_lower:
            new_stage_id = s['id']
        elif 'done' in name_lower or 'close' in name_lower:
            done_stage_id = s['id']
            
    # Fallbacks if specific names not found
    if not new_stage_id and stages: new_stage_id = stages[0]['id']
    if not done_stage_id and stages: done_stage_id = stages[-1]['id']

    # 3. DATA PREP: Create test alerts to make the filter meaningful
    # Get a dummy product and team
    products = models.execute_kw(db, uid, password, 'product.product', 'search', [], {'limit': 1})
    teams = models.execute_kw(db, uid, password, 'quality.alert.team', 'search', [], {'limit': 1})
    
    product_id = products[0] if products else False
    team_id = teams[0] if teams else False

    # Create alerts
    alerts_to_create = [
        {
            'name': 'TEST: Urgent New Issue (Should Show)',
            'product_id': product_id,
            'team_id': team_id,
            'stage_id': new_stage_id,
            'priority': '1', # High/Starred
            'description': 'Target for filter.'
        },
        {
            'name': 'TEST: Normal New Issue (Should Hide)',
            'product_id': product_id,
            'team_id': team_id,
            'stage_id': new_stage_id,
            'priority': '0', # Normal
            'description': 'Wrong priority.'
        },
        {
            'name': 'TEST: Urgent Done Issue (Should Hide)',
            'product_id': product_id,
            'team_id': team_id,
            'stage_id': done_stage_id,
            'priority': '1', # High
            'description': 'Wrong stage.'
        }
    ]
    
    for vals in alerts_to_create:
        # Check if already exists to avoid duplicates on re-run
        exists = models.execute_kw(db, uid, password, 'quality.alert', 'search', [[('name', '=', vals['name'])]])
        if not exists:
            models.execute_kw(db, uid, password, 'quality.alert', 'create', [vals])
            print(f"Created alert: {vals['name']}")

except Exception as e:
    print(f"Setup Error: {e}")
    sys.exit(1)
PYTHON_EOF

# Launch Firefox and navigate to Quality Alerts
# We use the list view so the filter bar is immediately accessible
ensure_firefox "http://localhost:8069/web#action=quality.quality_alert_action_team&view_type=list"

# Capture initial screenshot
echo "Capturing initial state..."
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="