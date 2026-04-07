#!/bin/bash
# Setup for sla_business_days_compliance task

echo "=== Setting up SLA Business Days Compliance Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ============================================================
# Clean up previous state to ensure clean run
# ============================================================
echo "Cleaning up previous task artifacts..."

# Drop View
mssql_query "IF OBJECT_ID('Sales.vw_ShippingSLABreach', 'V') IS NOT NULL DROP VIEW Sales.vw_ShippingSLABreach" "AdventureWorks2022"

# Drop Function
mssql_query "IF OBJECT_ID('dbo.fn_GetNetWorkingDays', 'FN') IS NOT NULL DROP FUNCTION dbo.fn_GetNetWorkingDays" "AdventureWorks2022"

# Drop Table
mssql_query "IF OBJECT_ID('Sales.HolidayReference', 'U') IS NOT NULL DROP TABLE Sales.HolidayReference" "AdventureWorks2022"

# Remove CSV
rm -f /home/ga/Documents/sla_breaches.csv

# ============================================================
# Ensure Azure Data Studio is running and connected
# ============================================================
echo "Ensuring Azure Data Studio is running..."

# Launch Azure Data Studio if not running
if ! pgrep -f "azuredatastudio" > /dev/null; then
    echo "Starting Azure Data Studio..."
    ADS_CMD="/snap/bin/azuredatastudio"
    [ ! -x "$ADS_CMD" ] && ADS_CMD="azuredatastudio"
    
    su - ga -c "DISPLAY=:1 $ADS_CMD > /tmp/ads.log 2>&1 &"
    
    # Wait for window
    for i in {1..45}; do
        if DISPLAY=:1 wmctrl -l | grep -qi "azure\|data studio"; then
            echo "ADS window detected"
            break
        fi
        sleep 1
    done
fi

# Maximize window
sleep 5
WID=$(DISPLAY=:1 wmctrl -l | grep -i "azure\|data studio" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz
fi

# Dismiss welcome/keyring dialogs
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="