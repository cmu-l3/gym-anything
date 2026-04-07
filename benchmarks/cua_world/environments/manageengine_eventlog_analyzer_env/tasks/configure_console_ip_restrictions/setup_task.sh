#!/bin/bash
echo "=== Setting up Configure Console IP Restrictions task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure EventLog Analyzer is running
wait_for_eventlog_analyzer 600

# Record initial configuration state (for comparison)
# We try to dump any existing IP restriction settings
echo "Recording initial DB state..."
ela_db_query "SELECT * FROM SystemConfig WHERE param_name LIKE '%HOST%' OR param_name LIKE '%IP%';" > /tmp/initial_db_state.txt 2>/dev/null || true

# Ensure Firefox is open and logged in
# We navigate to the Settings page to give a helpful starting point, 
# but not the exact deep link to security settings (agent must find it)
ensure_firefox_on_ela "/event/index.do#/settings/admin-settings"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="