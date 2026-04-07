#!/bin/bash
# Setup for dynamic_stockout_prediction_model task
echo "=== Setting up dynamic_stockout_prediction_model task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# ============================================================
# Clean up any previous task artifacts
# ============================================================
echo "Cleaning up previous task artifacts..."

# Drop stored procedure if it exists
mssql_query "
IF OBJECT_ID('Production.usp_GetCriticalStockouts', 'P') IS NOT NULL
    DROP PROCEDURE Production.usp_GetCriticalStockouts
" "AdventureWorks2022"

# Drop view if it exists
mssql_query "
IF OBJECT_ID('Production.vw_ProductStockoutProjection', 'V') IS NOT NULL
    DROP VIEW Production.vw_ProductStockoutProjection
" "AdventureWorks2022"

# Remove existing CSV
rm -f /home/ga/Documents/critical_stockouts.csv

echo "Cleanup complete."

# ============================================================
# Record initial state
# ============================================================
echo "Recording initial state..."
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Documents

# ============================================================
# Ensure Azure Data Studio is running and connected
# ============================================================
echo "Ensuring Azure Data Studio is running and connected..."

# Check if Azure Data Studio is already running
ADS_RUNNING=false
if pgrep -f "azuredatastudio" > /dev/null 2>&1; then
    ADS_RUNNING=true
    echo "Azure Data Studio is already running"
fi

# Launch Azure Data Studio if not running
if [ "$ADS_RUNNING" = false ]; then
    echo "Launching Azure Data Studio..."
    ADS_CMD="/snap/bin/azuredatastudio"
    if [ ! -x "$ADS_CMD" ]; then
        ADS_CMD="azuredatastudio"
    fi
    su - ga -c "DISPLAY=:1 $ADS_CMD > /tmp/azuredatastudio_task.log 2>&1 &"

    # Wait for Azure Data Studio window to appear
    echo "Waiting for Azure Data Studio window..."
    for i in $(seq 1 30); do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "azure\|data studio"; then
            echo "Azure Data Studio window detected after ${i}s"
            break
        fi
        sleep 1
    done
fi

# Give ADS time to fully initialize
sleep 5

# Bring Azure Data Studio window to foreground and maximize
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "azure\|data studio" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    echo "Azure Data Studio window activated and maximized"
fi

sleep 2

# Dismiss common startup dialogs
echo "Dismissing startup dialogs..."
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="