#!/bin/bash
echo "=== Setting up sales_inactivity_gap_analysis task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean up previous artifacts to ensure a fresh start
echo "Cleaning up database objects..."
mssql_query "IF OBJECT_ID('Sales.vw_2013_InactivityReport', 'V') IS NOT NULL DROP VIEW Sales.vw_2013_InactivityReport"
mssql_query "IF OBJECT_ID('Sales.tvf_GetSalesPersonMaxGap', 'IF') IS NOT NULL DROP FUNCTION Sales.tvf_GetSalesPersonMaxGap"
mssql_query "IF OBJECT_ID('Sales.tvf_GetSalesPersonMaxGap', 'TF') IS NOT NULL DROP FUNCTION Sales.tvf_GetSalesPersonMaxGap"

# Remove output file
rm -f /home/ga/Documents/inactivity_report_2013.csv

# Record initial state
echo "Recording initial state..."
ORDER_COUNT=$(mssql_count "Sales.SalesOrderHeader")
echo "Initial Order Count: $ORDER_COUNT" > /tmp/initial_state.txt

# Ensure Azure Data Studio is running and connected
echo "Ensuring Azure Data Studio is running..."

# Launch ADS if not running
if ! pgrep -f "azuredatastudio" > /dev/null 2>&1; then
    ADS_CMD="/snap/bin/azuredatastudio"
    [ -x "$ADS_CMD" ] || ADS_CMD="azuredatastudio"
    su - ga -c "DISPLAY=:1 $ADS_CMD > /tmp/ads.log 2>&1 &"
    
    # Wait for window
    for i in {1..45}; do
        if DISPLAY=:1 wmctrl -l | grep -qi "azure\|data studio"; then
            break
        fi
        sleep 1
    done
fi

# Maximize and focus
sleep 2
WID=$(DISPLAY=:1 wmctrl -l | grep -i "azure\|data studio" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz
fi

# Connect to SQL Server logic is handled by the agent (part of the task is to use the tool),
# but we ensure the server is up.
if ! mssql_is_running; then
    echo "ERROR: SQL Server is not running!"
    exit 1
fi

echo "=== Setup complete ==="