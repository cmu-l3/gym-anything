#!/bin/bash
echo "=== Setting up configure_private_sales_pipeline_sharing task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# 2. Reset the Potentials (Opportunities) module to the default 'Public' sharing access (permission = 0)
# In Vtiger, tabid for Potentials is typically 4, but we query it to be safe.
echo "Resetting Opportunities sharing rules to Public to ensure clean state..."
POTENTIALS_TABID=$(vtiger_db_query "SELECT tabid FROM vtiger_tab WHERE name='Potentials' LIMIT 1" | tr -d '[:space:]')

if [ -n "$POTENTIALS_TABID" ]; then
    vtiger_db_query "UPDATE vtiger_def_org_share SET permission=0 WHERE tabid=$POTENTIALS_TABID"
fi

# 3. Remove any existing custom sharing rules for Potentials (role to role)
echo "Cleaning up any existing custom sharing rules..."
vtiger_db_query "
DELETE r2r FROM vtiger_datashare_role2role r2r 
JOIN vtiger_datashare_module_rel mrel ON r2r.shareid = mrel.shareid 
WHERE mrel.tabid = $POTENTIALS_TABID
"

# 4. Ensure Firefox is open and logged into Vtiger CRM at the home dashboard
echo "Ensuring Vtiger is logged in..."
ensure_vtiger_logged_in "http://localhost:8000/index.php"
sleep 4

# 5. Maximize and bring to front
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# 6. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== configure_private_sales_pipeline_sharing task setup complete ==="