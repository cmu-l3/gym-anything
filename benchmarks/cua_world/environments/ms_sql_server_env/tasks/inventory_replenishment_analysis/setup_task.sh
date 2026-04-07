#!/bin/bash
set -e
echo "=== Setting up inventory_replenishment_analysis task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure SQL Server is running
if ! mssql_is_running; then
    echo "ERROR: SQL Server is not running!"
    exit 1
fi

# Clean up any previous attempts (Idempotency)
echo "Cleaning up previous objects..."
mssql_query "IF OBJECT_ID('Production.ReplenishmentQueue', 'U') IS NOT NULL DROP TABLE Production.ReplenishmentQueue" || true
mssql_query "IF OBJECT_ID('dbo.vw_InventoryHealthDashboard', 'V') IS NOT NULL DROP VIEW dbo.vw_InventoryHealthDashboard" || true
mssql_query "IF OBJECT_ID('dbo.fn_ProductDemandStats', 'IF') IS NOT NULL DROP FUNCTION dbo.fn_ProductDemandStats" || true
mssql_query "IF OBJECT_ID('dbo.fn_ProductDemandStats', 'TF') IS NOT NULL DROP FUNCTION dbo.fn_ProductDemandStats" || true

# Record initial state of source tables (for debugging/verification context)
echo "Recording source data state..."
PRODUCT_COUNT=$(mssql_query "SELECT COUNT(*) FROM Production.Product" | tr -d ' \r\n')
INVENTORY_COUNT=$(mssql_query "SELECT COUNT(*) FROM Production.ProductInventory" | tr -d ' \r\n')
SALES_COUNT=$(mssql_query "SELECT COUNT(*) FROM Sales.SalesOrderDetail" | tr -d ' \r\n')

echo "Source Data: Products=$PRODUCT_COUNT, Inventory=$INVENTORY_COUNT, SalesDetails=$SALES_COUNT"
echo "$PRODUCT_COUNT" > /tmp/initial_product_count.txt

# Ensure Azure Data Studio is running and ready for the user
if ! ads_is_running; then
    echo "Starting Azure Data Studio..."
    ADS_CMD="/snap/bin/azuredatastudio"
    [ -x "$ADS_CMD" ] || ADS_CMD="azuredatastudio"
    su - ga -c "DISPLAY=:1 $ADS_CMD > /tmp/azuredatastudio.log 2>&1 &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "azure\|data studio"; then
            echo "Azure Data Studio window detected"
            break
        fi
        sleep 1
    done
fi

# Maximize and focus ADS
sleep 5
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "azure|data studio" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Dismiss common startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="