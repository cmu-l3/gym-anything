#!/bin/bash
# Setup for multidimensional_sales_cube task
echo "=== Setting up multidimensional_sales_cube task ==="

source /workspace/scripts/task_utils.sh

# ============================================================
# Clean up any previous task artifacts
# ============================================================
echo "Cleaning up previous task artifacts..."

# Drop objects in reverse dependency order
mssql_query "
IF OBJECT_ID('dbo.vw_SalesCubeSummary', 'V') IS NOT NULL DROP VIEW dbo.vw_SalesCubeSummary;
IF OBJECT_ID('dbo.usp_ExportSalesCube', 'P') IS NOT NULL DROP PROCEDURE dbo.usp_ExportSalesCube;
IF OBJECT_ID('dbo.fn_SalesCube', 'IF') IS NOT NULL DROP FUNCTION dbo.fn_SalesCube;
IF OBJECT_ID('dbo.fn_SalesCube', 'TF') IS NOT NULL DROP FUNCTION dbo.fn_SalesCube;
IF OBJECT_ID('dbo.SalesCubeExport', 'U') IS NOT NULL DROP TABLE dbo.SalesCubeExport;
" "AdventureWorks2022"

# Clean up files
rm -f /home/ga/Documents/exports/sales_cube_report.txt 2>/dev/null || true
mkdir -p /home/ga/Documents/exports
chown -R ga:ga /home/ga/Documents

echo "Cleanup complete."

# ============================================================
# Record initial state
# ============================================================
echo "Recording initial state..."

# Calculate reference Grand Total Revenue for '2011-01-01' to '2014-12-31'
# This is used to verify the agent's aggregation logic later
REF_REVENUE=$(mssql_query "
    SELECT CAST(SUM(LineTotal) AS DECIMAL(20,2))
    FROM Sales.SalesOrderDetail sod
    JOIN Sales.SalesOrderHeader soh ON sod.SalesOrderID = soh.SalesOrderID
    WHERE soh.OrderDate >= '2011-01-01' AND soh.OrderDate <= '2014-12-31'
" "AdventureWorks2022" | tr -d ' \r\n')

echo "Reference Revenue: $REF_REVENUE" > /tmp/initial_state.txt
echo "Setup timestamp: $(date -Iseconds)" >> /tmp/initial_state.txt
date +%s > /tmp/task_start_time.txt

cat /tmp/initial_state.txt

# ============================================================
# Ensure Azure Data Studio is running and connected
# ============================================================
echo "Ensuring Azure Data Studio is running and connected..."

ADS_RUNNING=false
if pgrep -f "azuredatastudio" > /dev/null 2>&1; then
    ADS_RUNNING=true
    echo "Azure Data Studio is already running"
fi

if [ "$ADS_RUNNING" = false ]; then
    echo "Launching Azure Data Studio..."
    ADS_CMD="/snap/bin/azuredatastudio"
    if [ ! -x "$ADS_CMD" ]; then
        ADS_CMD="azuredatastudio"
    fi
    su - ga -c "DISPLAY=:1 $ADS_CMD > /tmp/azuredatastudio_task.log 2>&1 &"

    for i in $(seq 1 30); do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "azure\|data studio"; then
            echo "ADS window detected after ${i}s"
            break
        fi
        sleep 1
    done
fi

sleep 5

# Maximize window
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "azure\|data studio" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

sleep 2

# Dismiss common startup dialogs
DISPLAY=:1 xdotool key Tab Tab Return 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5

# ============================================================
# Connect to SQL Server
# ============================================================
echo "Establishing SQL Server connection..."
# Use Command Palette to connect
DISPLAY=:1 xdotool key F1
sleep 1
DISPLAY=:1 xdotool type 'new connection'
sleep 1
DISPLAY=:1 xdotool key Return
sleep 2

# Fill connection details
DISPLAY=:1 xdotool mousemove 1740 690 click 1
sleep 0.3
DISPLAY=:1 xdotool key ctrl+a
DISPLAY=:1 xdotool type 'localhost'
sleep 0.3

DISPLAY=:1 xdotool mousemove 1740 755 click 1
sleep 0.3
DISPLAY=:1 xdotool type 'sa'
sleep 0.3

DISPLAY=:1 xdotool mousemove 1740 785 click 1
sleep 0.3
DISPLAY=:1 xdotool type 'GymAnything#2024'
sleep 0.3

DISPLAY=:1 xdotool mousemove 1740 905 click 1
sleep 0.5
DISPLAY=:1 xdotool key t Return
sleep 0.5

DISPLAY=:1 xdotool mousemove 1770 1049 click 1
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="