#!/bin/bash
echo "=== Setting up simplify_app_menus task ==="

source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 1. Ensure the modules are actually enabled (presence = 0 in vtiger_tab)
vtiger_db_query "UPDATE vtiger_tab SET presence=0 WHERE name IN ('Campaigns', 'PriceBooks')"

# 2. Get the tab IDs for the modules
TABID_CAMP=$(vtiger_db_query "SELECT tabid FROM vtiger_tab WHERE name='Campaigns'" | tr -d '[:space:]')
TABID_PB=$(vtiger_db_query "SELECT tabid FROM vtiger_tab WHERE name='PriceBooks'" | tr -d '[:space:]')

# 3. Ensure they are currently mapped to their respective menus
if [ -n "$TABID_CAMP" ]; then
    EXISTS_CAMP=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_app2tab WHERE appname='MARKETING' AND tabid=$TABID_CAMP" | tr -d '[:space:]')
    if [ "$EXISTS_CAMP" -eq 0 ]; then
        MAX_SEQ=$(vtiger_db_query "SELECT MAX(sequence) FROM vtiger_app2tab WHERE appname='MARKETING'" | tr -d '[:space:]')
        MAX_SEQ=$((MAX_SEQ + 1))
        vtiger_db_query "INSERT INTO vtiger_app2tab (appname, tabid, sequence) VALUES ('MARKETING', $TABID_CAMP, $MAX_SEQ)"
    fi
fi

if [ -n "$TABID_PB" ]; then
    EXISTS_PB=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_app2tab WHERE appname='INVENTORY' AND tabid=$TABID_PB" | tr -d '[:space:]')
    if [ "$EXISTS_PB" -eq 0 ]; then
        MAX_SEQ=$(vtiger_db_query "SELECT MAX(sequence) FROM vtiger_app2tab WHERE appname='INVENTORY'" | tr -d '[:space:]')
        MAX_SEQ=$((MAX_SEQ + 1))
        vtiger_db_query "INSERT INTO vtiger_app2tab (appname, tabid, sequence) VALUES ('INVENTORY', $TABID_PB, $MAX_SEQ)"
    fi
fi

# 4. Navigate Firefox to the Menu Editor page via CRM settings
# This gives the agent a fair starting point, but they still need to perform the interactions
ensure_vtiger_logged_in "http://localhost:8000/index.php?module=MenuEditor&parent=Settings&view=Index"
sleep 3

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="