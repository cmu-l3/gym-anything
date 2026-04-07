#!/bin/bash
# Setup for product_copurchase_affinity task
echo "=== Setting up product_copurchase_affinity task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ============================================================
# Clean up previous state
# ============================================================
echo "Cleaning up previous task artifacts..."

# Drop objects if they exist to ensure a clean slate
mssql_query "
IF OBJECT_ID('dbo.vw_TopProductBundles', 'V') IS NOT NULL
    DROP VIEW dbo.vw_TopProductBundles;
IF OBJECT_ID('dbo.usp_MarketBasketAnalysis', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_MarketBasketAnalysis;
IF OBJECT_ID('dbo.ProductAffinityResults', 'U') IS NOT NULL
    DROP TABLE dbo.ProductAffinityResults;
" "AdventureWorks2022"

# Clean up exports
mkdir -p /home/ga/Documents/exports
rm -f /home/ga/Documents/exports/top_product_bundles.csv

# ============================================================
# Record initial state
# ============================================================
echo "Recording initial database state..."

# Count SalesOrderDetail rows to ensure DB is healthy
SOD_COUNT=$(mssql_query "SELECT COUNT(*) FROM Sales.SalesOrderDetail" "AdventureWorks2022" | tr -d ' \r\n')
echo "SalesOrderDetail row count: $SOD_COUNT" > /tmp/initial_state.txt
echo "Setup timestamp: $(date -Iseconds)" >> /tmp/initial_state.txt

# ============================================================
# Ensure Azure Data Studio is running and connected
# ============================================================
echo "Ensuring Azure Data Studio is running..."

if ! ads_is_running; then
    echo "Launching Azure Data Studio..."
    ADS_CMD="/snap/bin/azuredatastudio"
    if [ ! -x "$ADS_CMD" ]; then
        ADS_CMD="azuredatastudio"
    fi
    su - ga -c "DISPLAY=:1 $ADS_CMD > /tmp/azuredatastudio_task.log 2>&1 &"
    
    # Wait for window
    for i in {1..30}; do
        if get_ads_windows | grep -q .; then
            echo "ADS window detected"
            break
        fi
        sleep 1
    done
fi

# Maximize and focus
sleep 5
WID=$(get_ads_windows | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Dismiss welcome/telemetry dialogs if they appear
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Establish/Verify connection (attempting to use command palette to connect localhost)
echo "Ensuring connection..."
# Focus window
if [ -n "$WID" ]; then DISPLAY=:1 wmctrl -ia "$WID"; fi
sleep 1

# Open New Connection via Command Palette
DISPLAY=:1 xdotool key F1
sleep 1
DISPLAY=:1 xdotool type "New Connection"
sleep 0.5
DISPLAY=:1 xdotool key Return
sleep 2

# Fill details: Server=localhost
DISPLAY=:1 xdotool type "localhost"
sleep 0.5
DISPLAY=:1 xdotool key Tab
# Auth type (skip if default)
DISPLAY=:1 xdotool key Tab
# User=sa
DISPLAY=:1 xdotool type "sa"
sleep 0.5
DISPLAY=:1 xdotool key Tab
# Pass
DISPLAY=:1 xdotool type "GymAnything#2024"
sleep 0.5
# Tab to Connect or Trust Server Cert
DISPLAY=:1 xdotool key Tab
DISPLAY=:1 xdotool key Tab
DISPLAY=:1 xdotool key Tab
# Might need to hit Enter to connect
DISPLAY=:1 xdotool key Return
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="