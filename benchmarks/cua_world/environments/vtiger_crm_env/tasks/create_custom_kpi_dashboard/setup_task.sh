#!/bin/bash
echo "=== Setting up create_custom_kpi_dashboard task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Clean up any existing 'Sales KPIs' dashboard to ensure a clean state
DASH_ID=$(vtiger_db_query "SELECT id FROM vtiger_module_dashboards WHERE dashboardname='Sales KPIs' LIMIT 1" | tr -d '[:space:]')
if [ -n "$DASH_ID" ]; then
    echo "WARNING: 'Sales KPIs' dashboard already exists, removing..."
    vtiger_db_query "DELETE FROM vtiger_module_dashboard_widgets WHERE dashboardid=$DASH_ID"
    vtiger_db_query "DELETE FROM vtiger_module_dashboards WHERE id=$DASH_ID"
fi

# 2. Record initial counts for anti-gaming verification
INITIAL_DASHBOARD_COUNT=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_module_dashboards" | tr -d '[:space:]' || echo "0")
INITIAL_WIDGET_COUNT=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_module_dashboard_widgets" | tr -d '[:space:]' || echo "0")

echo "Initial dashboard count: $INITIAL_DASHBOARD_COUNT"
echo "Initial total widget count: $INITIAL_WIDGET_COUNT"

echo "$INITIAL_DASHBOARD_COUNT" > /tmp/initial_dashboard_count.txt
echo "$INITIAL_WIDGET_COUNT" > /tmp/initial_widget_count.txt
chmod 666 /tmp/initial_dashboard_count.txt /tmp/initial_widget_count.txt 2>/dev/null || true

# 3. Ensure logged in and navigate to the Dashboard/Home module
# Usually accessible at index.php?module=Home&view=DashBoard
ensure_vtiger_logged_in "http://localhost:8000/index.php?module=Home&view=DashBoard"
sleep 5

# 4. Take initial screenshot
take_screenshot /tmp/create_custom_kpi_dashboard_initial.png

echo "=== create_custom_kpi_dashboard task setup complete ==="
echo "Task: Create 'Sales KPIs' dashboard and add at least 3 widgets."