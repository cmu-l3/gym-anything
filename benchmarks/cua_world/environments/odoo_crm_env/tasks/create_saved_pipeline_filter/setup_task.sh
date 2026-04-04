#!/bin/bash
set -e
echo "=== Setting up create_saved_pipeline_filter task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 2. Wait for Odoo to be ready
wait_for_odoo

# 3. Clean up any pre-existing filter named "High Value Deals" to ensure clean state
echo "Cleaning up old filters..."
odoo_db_query "DELETE FROM ir_filters WHERE name ILIKE '%High Value Deals%' AND model_id = 'crm.lead';" || true

# 4. Seed opportunities with varied expected revenues (Visual feedback for agent)
echo "Seeding opportunities..."
python3 - <<'PYEOF'
import xmlrpc.client
import sys

URL = "http://localhost:8069"
DB = "odoodb"
USER = "admin"
PASS = "admin"

try:
    common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
    uid = common.authenticate(DB, USER, PASS, {})
    models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')

    # Get pipeline stages
    stages = models.execute_kw(DB, uid, PASS, 'crm.stage', 'search_read',
        [[]], {'fields': ['id', 'name'], 'order': 'sequence'})
    stage_ids = [s['id'] for s in stages]
    if not stage_ids:
        # Fallback if no stages exist (unlikely)
        stage_ids = [False]

    # Mix of High Value (>= 50k) and Low Value (< 50k) opportunities
    opps = [
        # High Value
        {"name": "Enterprise License - Acme Corp", "expected_revenue": 75000, "priority": "3"},
        {"name": "Global Rollout - Globex", "expected_revenue": 120000, "priority": "2"},
        {"name": "Data Center Upgrade - Initech", "expected_revenue": 55000, "priority": "1"},
        {"name": "Security Audit - Umbrella Corp", "expected_revenue": 200000, "priority": "3"},
        # Low Value
        {"name": "Consulting - Mom & Pop", "expected_revenue": 5000, "priority": "0"},
        {"name": "Website Fix - Local Bakery", "expected_revenue": 1200, "priority": "1"},
        {"name": "Training Session - StartUp Inc", "expected_revenue": 25000, "priority": "1"},
        {"name": "Logo Design - Cafe 80s", "expected_revenue": 45000, "priority": "2"},
    ]

    for i, opp in enumerate(opps):
        opp['type'] = 'opportunity'
        opp['stage_id'] = stage_ids[i % len(stage_ids)]
        
        # Check if exists to avoid duplicates
        existing = models.execute_kw(DB, uid, PASS, 'crm.lead', 'search', [[['name', '=', opp['name']]]])
        if not existing:
            models.execute_kw(DB, uid, PASS, 'crm.lead', 'create', [opp])
            print(f"Created: {opp['name']}")
        else:
            print(f"Exists: {opp['name']}")

except Exception as e:
    print(f"Seeding failed: {e}", file=sys.stderr)
PYEOF

# 5. Ensure Firefox is running and logged in
ensure_odoo_logged_in "http://localhost:8069/web#action=209&cids=1&menu_id=139"
sleep 5

# 6. Maximize Firefox window (CRITICAL for visibility)
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# 7. Take initial screenshot
echo "Capturing initial state..."
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="