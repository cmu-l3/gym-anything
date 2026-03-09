#!/bin/bash
# Setup for vendor_performance_analytics task
echo "=== Setting up vendor_performance_analytics task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# ============================================================
# Clean up any previous task state
# ============================================================
echo "Cleaning up previous task artifacts..."

# Drop stored procedure if it exists
mssql_query "
IF OBJECT_ID('dbo.usp_VendorPerformanceReport', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_VendorPerformanceReport
" "AdventureWorks2022"

# Drop table before schema (must drop objects in schema before dropping schema)
mssql_query "
IF OBJECT_ID('Analytics.VendorPerformance', 'U') IS NOT NULL
    DROP TABLE Analytics.VendorPerformance
" "AdventureWorks2022"

# Drop the Analytics schema if it exists (and is now empty)
mssql_query "
IF EXISTS (SELECT * FROM sys.schemas WHERE name = 'Analytics')
    EXEC('DROP SCHEMA Analytics')
" "AdventureWorks2022"

echo "Cleanup complete."

# ============================================================
# Record initial state
# ============================================================
echo "Recording initial state..."

VENDOR_COUNT=$(mssql_query "SELECT COUNT(*) FROM Purchasing.Vendor" "AdventureWorks2022" | tr -d ' \r\n')
POH_COUNT=$(mssql_query "SELECT COUNT(*) FROM Purchasing.PurchaseOrderHeader" "AdventureWorks2022" | tr -d ' \r\n')
SCHEMA_EXISTS=$(mssql_query "SELECT COUNT(*) FROM sys.schemas WHERE name = 'Analytics'" "AdventureWorks2022" | tr -d ' \r\n')
PROC_EXISTS=$(mssql_query "SELECT COUNT(*) FROM sys.procedures WHERE name = 'usp_VendorPerformanceReport'" "AdventureWorks2022" | tr -d ' \r\n')

echo "Vendor count: $VENDOR_COUNT" > /tmp/initial_state.txt
echo "PO header count: $POH_COUNT" >> /tmp/initial_state.txt
echo "Analytics schema exists: $SCHEMA_EXISTS" >> /tmp/initial_state.txt
echo "Procedure exists: $PROC_EXISTS" >> /tmp/initial_state.txt
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

    echo "Waiting for Azure Data Studio window..."
    for i in $(seq 1 30); do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "azure\|data studio"; then
            echo "Azure Data Studio window detected after ${i}s"
            break
        fi
        sleep 1
    done
fi

sleep 5

# Bring ADS to foreground and maximize
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "azure\|data studio" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

sleep 2

# Dismiss startup dialogs
DISPLAY=:1 xdotool key Tab Tab Return
sleep 1
DISPLAY=:1 xdotool mousemove 1879 1015 click 1
sleep 1
DISPLAY=:1 xdotool key Escape
sleep 0.5
DISPLAY=:1 xdotool key Escape
sleep 0.5
DISPLAY=:1 xdotool mousemove 960 540 click 1
sleep 0.5

# ============================================================
# Connect to SQL Server via Command Palette
# ============================================================
echo "Establishing SQL Server connection..."

DISPLAY=:1 xdotool key F1
sleep 1
DISPLAY=:1 xdotool type 'new connection'
sleep 1
DISPLAY=:1 xdotool key Return
sleep 2

# Fill connection fields
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

# Wait for connection
CONNECTION_ESTABLISHED=false
for i in $(seq 1 15); do
    TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "azure" | head -1)
    if echo "$TITLE" | grep -qi "localhost.*Azure"; then
        CONNECTION_ESTABLISHED=true
        echo "Connection established after ${i}s"
        break
    fi
    if [ "$i" -eq 8 ]; then
        DISPLAY=:1 xdotool key Return
    fi
    sleep 1
done

if [ "$CONNECTION_ESTABLISHED" = "false" ]; then
    echo "Retrying connection..."
    DISPLAY=:1 xdotool key Escape
    sleep 0.5
    DISPLAY=:1 xdotool key F1
    sleep 1
    DISPLAY=:1 xdotool type 'new connection'
    sleep 1
    DISPLAY=:1 xdotool key Return
    sleep 2
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
    sleep 8
fi

# Open new query editor
DISPLAY=:1 xdotool key F1
sleep 0.5
DISPLAY=:1 xdotool type 'new query'
sleep 0.5
DISPLAY=:1 xdotool key Return
sleep 2

# Clear query editor
DISPLAY=:1 xdotool mousemove 600 400 click 1
sleep 0.3
DISPLAY=:1 xdotool key ctrl+a Delete
sleep 0.5

# Final cleanup
DISPLAY=:1 xdotool mousemove 1889 917 click 1
sleep 0.5
DISPLAY=:1 xdotool key Escape
sleep 0.5
DISPLAY=:1 xdotool mousemove 960 400 click 1
sleep 0.5

# Take initial screenshot
DISPLAY=:1 import -window root /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== Task setup complete ==="
echo ""
echo "Azure Data Studio is running and connected to SQL Server."
echo ""
echo "Task: Vendor Performance Analytics System"
echo "1. Create schema 'Analytics' in AdventureWorks2022"
echo "2. Create table 'Analytics.VendorPerformance' with 7 specific columns"
echo "3. Create stored procedure 'dbo.usp_VendorPerformanceReport(@StartDate, @EndDate)'"
echo "4. Execute: EXEC usp_VendorPerformanceReport '2013-01-01', '2014-01-01'"
echo ""
exit 0
