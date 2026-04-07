#!/bin/bash
# Setup for sales_quota_attainment_history task
echo "=== Setting up sales_quota_attainment_history task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create documents directory if not exists
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Documents

# Clean up previous artifacts
rm -f /home/ga/Documents/quota_attainment_2012.csv 2>/dev/null || true

# Drop the view if it exists from a previous run
echo "Cleaning up any existing view..."
mssql_query "IF OBJECT_ID('Sales.vw_HistoricalQuotaAttainment', 'V') IS NOT NULL DROP VIEW Sales.vw_HistoricalQuotaAttainment" || true

# Record initial database state for debugging/logging
echo "Recording initial state..."
QUOTA_COUNT=$(mssql_count "Sales.SalesPersonQuotaHistory")
ORDER_COUNT=$(mssql_count "Sales.SalesOrderHeader")

echo "Quota History Rows: $QUOTA_COUNT" > /tmp/initial_state.txt
echo "Order Header Rows: $ORDER_COUNT" >> /tmp/initial_state.txt
echo "Setup timestamp: $(date -Iseconds)" >> /tmp/initial_state.txt

# ============================================================
# Ensure Azure Data Studio is running and connected
# ============================================================
echo "Ensuring Azure Data Studio is running and connected..."

# Launch ADS if not running
if ! pgrep -f "azuredatastudio" > /dev/null 2>&1; then
    echo "Launching Azure Data Studio..."
    ADS_CMD="/snap/bin/azuredatastudio"
    [ -x "$ADS_CMD" ] || ADS_CMD="azuredatastudio"
    
    su - ga -c "DISPLAY=:1 $ADS_CMD > /tmp/ads_launch.log 2>&1 &"
    
    # Wait for window
    for i in {1..45}; do
        if DISPLAY=:1 wmctrl -l | grep -qi "azure\|data studio"; then
            echo "ADS Window detected."
            break
        fi
        sleep 1
    done
fi

sleep 5

# Maximize Window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "azure\|data studio" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Dismiss Dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Connect to SQL Server (Command Palette -> New Connection)
echo "Automating connection..."
DISPLAY=:1 xdotool key F1
sleep 1
DISPLAY=:1 xdotool type "new connection"
sleep 1
DISPLAY=:1 xdotool key Return
sleep 3

# Fill Connection Details (Blind typing sequence based on default layout)
# Server
DISPLAY=:1 xdotool type "localhost"
DISPLAY=:1 xdotool key Tab
# Auth Type (SQL Login)
DISPLAY=:1 xdotool key Down
DISPLAY=:1 xdotool key Tab
# User
DISPLAY=:1 xdotool type "sa"
DISPLAY=:1 xdotool key Tab
# Password
DISPLAY=:1 xdotool type "GymAnything#2024"
DISPLAY=:1 xdotool key Tab
# Remember Password
DISPLAY=:1 xdotool key space
DISPLAY=:1 xdotool key Tab
# Database
DISPLAY=:1 xdotool type "AdventureWorks2022"
DISPLAY=:1 xdotool key Tab
# Trust Server Cert (Critical)
DISPLAY=:1 xdotool key space 
DISPLAY=:1 xdotool key Return # Connect

sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="