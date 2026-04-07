#!/bin/bash
# Setup for reseller_order_sessionization task
echo "=== Setting up Reseller Order Sessionization Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ============================================================
# 1. Clean up any previous attempts (Idempotency)
# ============================================================
echo "Cleaning up previous database objects..."

# We need to drop dependent objects first
mssql_query "
IF OBJECT_ID('Logistics.usp_GenerateRestockingSessions', 'P') IS NOT NULL
    DROP PROCEDURE Logistics.usp_GenerateRestockingSessions;

IF OBJECT_ID('Logistics.ResellerRestockingSessions', 'U') IS NOT NULL
    DROP TABLE Logistics.ResellerRestockingSessions;

IF EXISTS (SELECT * FROM sys.schemas WHERE name = 'Logistics')
    DROP SCHEMA Logistics;
" "AdventureWorks2022"

# ============================================================
# 2. Record Initial State
# ============================================================
echo "Recording initial state..."

# Count existing reseller orders to ensure data exists
RESELLER_ORDER_COUNT=$(mssql_query "SELECT COUNT(*) FROM Sales.SalesOrderHeader WHERE OnlineOrderFlag = 0" "AdventureWorks2022" | tr -d ' \r\n')
echo "Reseller Orders Available: $RESELLER_ORDER_COUNT" > /tmp/initial_state.txt

# ============================================================
# 3. Ensure Azure Data Studio is Running
# ============================================================
echo "Ensuring Azure Data Studio is ready..."

if ! ads_is_running; then
    echo "Starting Azure Data Studio..."
    su - ga -c "DISPLAY=:1 azuredatastudio > /tmp/ads.log 2>&1 &"
    
    # Wait for window
    for i in {1..30}; do
        if get_ads_windows > /dev/null; then
            echo "ADS window detected."
            break
        fi
        sleep 1
    done
fi

# Maximize and Focus
WID=$(get_ads_windows | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    # Dismiss potential startup dialogs
    sleep 2
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="