#!/bin/bash
# Setup script for hr_employee_survey_logic task
# Ensures Surveys app is installed and cleans up any previous attempts.

echo "=== Setting up HR Employee Survey Logic Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record start time
date +%s > /tmp/task_start_timestamp

# Wait for Odoo to be ready
echo "Waiting for Odoo..."
for i in $(seq 1 30); do
    if curl -s "http://localhost:8069/web/login" | grep -q "Odoo"; then
        break
    fi
    sleep 2
done

# Run Python setup via XML-RPC to ensure module is installed and clean state
python3 << 'PYEOF'
import xmlrpc.client
import sys
import time

URL = 'http://localhost:8069'
DB = 'odoo_demo'
USERNAME = 'admin@example.com'
PASSWORD = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
    uid = common.authenticate(DB, USERNAME, PASSWORD, {})
    if not uid:
        print("Authentication failed")
        sys.exit(1)
    models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')
except Exception as e:
    print(f"Connection error: {e}")
    sys.exit(1)

def execute(model, method, args=None, kwargs=None):
    return models.execute_kw(DB, uid, PASSWORD, model, method, args or [], kwargs or {})

# 1. Check if 'survey' module is installed
print("Checking 'survey' module state...")
module = execute('ir.module.module', 'search_read', 
    [[['name', '=', 'survey']]], 
    {'fields': ['state']})

if module and module[0]['state'] != 'installed':
    print("Installing 'survey' module (this may take a moment)...")
    execute('ir.module.module', 'button_immediate_install', [[module[0]['id']]])
    time.sleep(5) 
else:
    print("'survey' module is already installed.")

# 2. Clean up any existing surveys with the target title to prevent ambiguity
target_title = "Remote Work Readiness 2026"
existing = execute('survey.survey', 'search', [[['title', 'ilike', target_title]]])
if existing:
    print(f"Removing {len(existing)} existing survey(s) with title '{target_title}'...")
    execute('survey.survey', 'unlink', [existing])

print("Setup complete.")
PYEOF

# Ensure Firefox is running and focused
echo "Launching Firefox..."
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8069/web' > /dev/null 2>&1 &"
    sleep 5
fi

# Maximize Firefox
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="