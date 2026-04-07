#!/bin/bash
# Setup script for email_marketing_campaign_setup task
# 1. Installs mass_mailing module
# 2. Creates the lead CSV file on Desktop
# 3. Calculates target schedule date for verification

echo "=== Setting up Email Marketing Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure mass_mailing is installed via XML-RPC
echo "Checking/Installing Email Marketing module..."
python3 << 'PYEOF'
import xmlrpc.client
import sys
import time

URL = 'http://localhost:8069'
DB = 'odoo_demo'
USERNAME = 'admin@example.com'
PASSWORD = 'admin'

# Wait for Odoo to be ready
for i in range(30):
    try:
        common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
        uid = common.authenticate(DB, USERNAME, PASSWORD, {})
        if uid:
            break
    except Exception:
        time.sleep(2)
else:
    print("Failed to connect to Odoo")
    sys.exit(1)

models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')

# Check if module is installed
module_name = 'mass_mailing'
installed = models.execute_kw(DB, uid, PASSWORD, 'ir.module.module', 'search_count', 
    [[['name', '=', module_name], ['state', '=', 'installed']]])

if not installed:
    print(f"Installing {module_name}...")
    # Find module id
    ids = models.execute_kw(DB, uid, PASSWORD, 'ir.module.module', 'search', 
        [[['name', '=', module_name]]])
    if ids:
        models.execute_kw(DB, uid, PASSWORD, 'ir.module.module', 'button_immediate_install', [ids])
        print("Module installed.")
    else:
        print("Module not found!")
else:
    print("Email Marketing module already installed.")
PYEOF

# 2. Create the CSV file
echo "Creating leads CSV..."
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/eco_leads.csv << 'EOF'
Name,Email
Sarah Green,sarah.green@example.org
David River,driver@naturemail.net
Eco Supplies HQ,purchasing@ecosupplies.test
EOF
chown ga:ga /home/ga/Desktop/eco_leads.csv

# 3. Calculate target schedule date (Today + 3 days) for verification reference
# Format: YYYY-MM-DD
TARGET_DATE=$(date -d "+3 days" +%Y-%m-%d)
echo "Target schedule date: $TARGET_DATE"

cat > /tmp/marketing_setup.json << EOF
{
    "target_date": "$TARGET_DATE",
    "setup_timestamp": $(date +%s)
}
EOF

# 4. Prepare UI
# Ensure Firefox is open
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8069/web/login?db=odoo_demo' &"
    sleep 5
fi

# Maximize window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="