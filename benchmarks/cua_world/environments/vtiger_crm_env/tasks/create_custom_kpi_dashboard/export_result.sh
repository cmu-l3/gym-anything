#!/bin/bash
echo "=== Exporting create_custom_kpi_dashboard results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/create_custom_kpi_dashboard_final.png

# Retrieve timestamps and initial counts
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
INITIAL_DASHBOARD_COUNT=$(cat /tmp/initial_dashboard_count.txt 2>/dev/null || echo "0")
INITIAL_WIDGET_COUNT=$(cat /tmp/initial_widget_count.txt 2>/dev/null || echo "0")

# Retrieve current counts
CURRENT_DASHBOARD_COUNT=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_module_dashboards" | tr -d '[:space:]' || echo "0")
CURRENT_WIDGET_COUNT=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_module_dashboard_widgets" | tr -d '[:space:]' || echo "0")

# Check if the expected dashboard tab was created
DASHBOARD_DATA=$(vtiger_db_query "SELECT id, dashboardname, userid FROM vtiger_module_dashboards WHERE dashboardname='Sales KPIs' ORDER BY id DESC LIMIT 1")

DASHBOARD_FOUND="false"
D_ID=""
D_NAME=""
D_USERID=""
WIDGETS_ON_DASHBOARD="0"

if [ -n "$DASHBOARD_DATA" ]; then
    DASHBOARD_FOUND="true"
    D_ID=$(echo "$DASHBOARD_DATA" | awk -F'\t' '{print $1}')
    D_NAME=$(echo "$DASHBOARD_DATA" | awk -F'\t' '{print $2}')
    D_USERID=$(echo "$DASHBOARD_DATA" | awk -F'\t' '{print $3}')
    
    # Count widgets specifically associated with this new dashboard tab
    WIDGETS_ON_DASHBOARD=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_module_dashboard_widgets WHERE dashboardid=$D_ID" | tr -d '[:space:]' || echo "0")
fi

# Check if application was running
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

RESULT_JSON=$(cat << JSONEOF
{
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "app_was_running": $APP_RUNNING,
  "initial_dashboard_count": $INITIAL_DASHBOARD_COUNT,
  "current_dashboard_count": $CURRENT_DASHBOARD_COUNT,
  "initial_widget_count": $INITIAL_WIDGET_COUNT,
  "current_widget_count": $CURRENT_WIDGET_COUNT,
  "dashboard_found": $DASHBOARD_FOUND,
  "dashboard_id": "$D_ID",
  "dashboard_name": "$(json_escape "${D_NAME:-}")",
  "dashboard_userid": "$D_USERID",
  "widgets_on_dashboard": $WIDGETS_ON_DASHBOARD
}
JSONEOF
)

safe_write_result "/tmp/custom_dashboard_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/custom_dashboard_result.json"
cat /tmp/custom_dashboard_result.json
echo "=== create_custom_kpi_dashboard export complete ==="