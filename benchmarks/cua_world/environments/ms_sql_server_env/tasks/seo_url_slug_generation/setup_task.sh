#!/bin/bash
# Setup for seo_url_slug_generation task
echo "=== Setting up seo_url_slug_generation task ==="

source /workspace/scripts/task_utils.sh

# ============================================================
# Clean up previous state
# ============================================================
echo "Cleaning up previous task artifacts..."

# Drop view if exists
mssql_query "IF OBJECT_ID('Production.vw_ProductSEO', 'V') IS NOT NULL DROP VIEW Production.vw_ProductSEO" "AdventureWorks2022"

# Drop function if exists
mssql_query "IF OBJECT_ID('dbo.fn_CreateSlug', 'FN') IS NOT NULL DROP FUNCTION dbo.fn_CreateSlug" "AdventureWorks2022"

# Remove export file
rm -f /home/ga/Documents/product_771_slug.json

echo "Cleanup complete."

# ============================================================
# Record initial state
# ============================================================
echo "Recording initial state..."
date +%s > /tmp/task_start_time.txt
mssql_count "Production.Product" > /tmp/initial_product_count.txt

# ============================================================
# Ensure Azure Data Studio is running and connected
# ============================================================
echo "Ensuring Azure Data Studio is running and connected..."

# Launch ADS if not running
if ! pgrep -f "azuredatastudio" > /dev/null; then
    echo "Launching Azure Data Studio..."
    ADS_CMD="/snap/bin/azuredatastudio"
    if [ ! -x "$ADS_CMD" ]; then ADS_CMD="azuredatastudio"; fi
    su - ga -c "DISPLAY=:1 $ADS_CMD > /tmp/azuredatastudio_task.log 2>&1 &"
    
    # Wait for window
    for i in {1..45}; do
        if DISPLAY=:1 wmctrl -l | grep -qi "azure\|data studio"; then
            echo "ADS window detected"
            break
        fi
        sleep 1
    done
fi

sleep 5

# Maximize window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "azure\|data studio" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Dismiss startup dialogs (Welcome, Keyring, etc.)
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
# Click center to focus editor
DISPLAY=:1 xdotool mousemove 960 540 click 1

# Connect to SQL Server
echo "Connecting to SQL Server..."
DISPLAY=:1 xdotool key F1
sleep 1
DISPLAY=:1 xdotool type 'new connection'
sleep 1
DISPLAY=:1 xdotool key Return
sleep 3

# Fill connection details
# Server
DISPLAY=:1 xdotool mousemove 1740 690 click 1
sleep 0.5
DISPLAY=:1 xdotool key ctrl+a
DISPLAY=:1 xdotool type 'localhost'
sleep 0.5
# Username
DISPLAY=:1 xdotool mousemove 1740 755 click 1
sleep 0.5
DISPLAY=:1 xdotool type 'sa'
sleep 0.5
# Password
DISPLAY=:1 xdotool mousemove 1740 785 click 1
sleep 0.5
DISPLAY=:1 xdotool type 'GymAnything#2024'
sleep 0.5
# Trust Cert
DISPLAY=:1 xdotool mousemove 1740 905 click 1
sleep 0.5
DISPLAY=:1 xdotool key t Return
sleep 0.5
# Connect
DISPLAY=:1 xdotool mousemove 1770 1049 click 1
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="