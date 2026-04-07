#!/bin/bash
# Setup for financial_ledger_etl_transformation task
echo "=== Setting up Financial Ledger ETL Task ==="

source /workspace/scripts/task_utils.sh

# ============================================================
# Clean up any previous task state
# ============================================================
echo "Cleaning up previous task artifacts..."

# Drop objects in reverse dependency order
mssql_query "
IF OBJECT_ID('Finance.vw_UnbalancedTransactions', 'V') IS NOT NULL DROP VIEW Finance.vw_UnbalancedTransactions;
IF OBJECT_ID('Finance.usp_PostSalesToGL', 'P') IS NOT NULL DROP PROCEDURE Finance.usp_PostSalesToGL;
IF OBJECT_ID('Finance.GeneralLedger', 'U') IS NOT NULL DROP TABLE Finance.GeneralLedger;
IF OBJECT_ID('Finance.ChartOfAccounts', 'U') IS NOT NULL DROP TABLE Finance.ChartOfAccounts;
IF EXISTS (SELECT * FROM sys.schemas WHERE name = 'Finance') EXEC('DROP SCHEMA Finance');
" "AdventureWorks2022"

echo "Cleanup complete."

# ============================================================
# Record initial state
# ============================================================
echo "Recording initial state..."

# Count source records for Q1 2013 to establish baseline
SOURCE_COUNT=$(mssql_query "SELECT COUNT(*) FROM Sales.SalesOrderHeader WHERE OrderDate BETWEEN '2013-01-01' AND '2013-03-31'" "AdventureWorks2022" | tr -d ' \r\n')
echo "Source Orders (Q1 2013): $SOURCE_COUNT" > /tmp/initial_state.txt
echo "Setup timestamp: $(date -Iseconds)" >> /tmp/initial_state.txt

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

# Dismiss startup dialogs
sleep 2
DISPLAY=:1 xdotool key Tab Tab Return 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Connect to SQL Server via Command Palette to ensure connection is ready
echo "Establishing SQL Server connection..."
DISPLAY=:1 xdotool key F1
sleep 1
DISPLAY=:1 xdotool type 'new connection'
sleep 1
DISPLAY=:1 xdotool key Return
sleep 2
# Fill connection details (Server, User, Pass)
DISPLAY=:1 xdotool type 'localhost'
DISPLAY=:1 xdotool key Tab
DISPLAY=:1 xdotool type 'SqlLogin'
DISPLAY=:1 xdotool key Tab
DISPLAY=:1 xdotool type 'sa'
DISPLAY=:1 xdotool key Tab
DISPLAY=:1 xdotool type 'GymAnything#2024'
DISPLAY=:1 xdotool key Return
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="