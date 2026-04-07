#!/bin/bash
echo "=== Setting up wac_inventory_ledger task ==="

source /workspace/scripts/task_utils.sh

# Delete stale outputs BEFORE recording timestamp
rm -f /home/ga/Documents/exports/cost_variance.csv 2>/dev/null
rm -f /tmp/wac_result.json 2>/dev/null || sudo rm -f /tmp/wac_result.json 2>/dev/null || true
rm -f /tmp/task_initial.png 2>/dev/null
rm -f /tmp/task_final.png 2>/dev/null

# Record start time
date +%s > /tmp/task_start_time.txt

# ── Clean up any existing SQL objects (reverse dependency order) ──────────────
mssql_query "IF OBJECT_ID('Production.vw_CostVarianceReport', 'V') IS NOT NULL DROP VIEW Production.vw_CostVarianceReport;" "AdventureWorks2022"
mssql_query "IF OBJECT_ID('Production.usp_BuildWACLedger', 'P') IS NOT NULL DROP PROCEDURE Production.usp_BuildWACLedger;" "AdventureWorks2022"
mssql_query "IF OBJECT_ID('Production.InventoryLedger', 'U') IS NOT NULL DROP TABLE Production.InventoryLedger;" "AdventureWorks2022"

# ── Ensure export directory exists ────────────────────────────────────────────
mkdir -p /home/ga/Documents/exports
chown -R ga:ga /home/ga/Documents 2>/dev/null || true

# ── Verify SQL Server is running ──────────────────────────────────────────────
if ! mssql_is_running; then
    echo "WARNING: SQL Server may not be running"
fi

# Verify source table exists
TXN_COUNT=$(mssql_query "SELECT COUNT(*) FROM Production.TransactionHistory" "AdventureWorks2022" 2>/dev/null | tr -d ' \r\n')
echo "Production.TransactionHistory rows: ${TXN_COUNT:-unknown}"

# ── Remove untrusted desktop shortcut (prevents blocking GNOME dialog) ────────
rm -f /home/ga/Desktop/AzureDataStudio.desktop 2>/dev/null || true

# ── Launch ADS if not running ─────────────────────────────────────────────────
if ! pgrep -f "azuredatastudio" > /dev/null; then
    ADS_CMD="/snap/bin/azuredatastudio"
    [ -x "$ADS_CMD" ] || ADS_CMD="azuredatastudio"
    su - ga -c "DISPLAY=:1 $ADS_CMD > /tmp/ads.log 2>&1 &"
    for i in {1..45}; do
        if DISPLAY=:1 wmctrl -l | grep -qi "azure\|data studio"; then break; fi
        sleep 1
    done
fi

# ── Focus and maximize ADS window ─────────────────────────────────────────────
sleep 5
WID=$(DISPLAY=:1 wmctrl -l | grep -i "azure\|data studio" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# ── Dismiss startup dialogs ──────────────────────────────────────────────────
DISPLAY=:1 xdotool key Tab Tab Return       # OS keyring dialog
sleep 1
DISPLAY=:1 xdotool mousemove 1879 1015 click 1  # Preview features "No"
sleep 1
DISPLAY=:1 xdotool key Escape
sleep 0.5
DISPLAY=:1 xdotool key Escape
sleep 0.5
DISPLAY=:1 xdotool mousemove 960 540 click 1    # Click main editor area
sleep 0.5

# ── Establish connection via Command Palette ──────────────────────────────────
DISPLAY=:1 xdotool key F1
sleep 1
DISPLAY=:1 xdotool type 'new connection'
sleep 1
DISPLAY=:1 xdotool key Return
sleep 2

# Fill connection fields (1920x1080 coordinates)
DISPLAY=:1 xdotool mousemove 1740 690 click 1; sleep 0.3   # Server field
DISPLAY=:1 xdotool key ctrl+a
DISPLAY=:1 xdotool type 'localhost'; sleep 0.3
DISPLAY=:1 xdotool mousemove 1740 755 click 1; sleep 0.3   # User name
DISPLAY=:1 xdotool type 'sa'; sleep 0.3
DISPLAY=:1 xdotool mousemove 1740 785 click 1; sleep 0.3   # Password
DISPLAY=:1 xdotool type 'GymAnything#2024'; sleep 0.3
DISPLAY=:1 xdotool mousemove 1740 905 click 1; sleep 0.5   # Trust cert dropdown
DISPLAY=:1 xdotool key t Return; sleep 0.5                   # Select "True"
DISPLAY=:1 xdotool mousemove 1770 1049 click 1              # Connect button
sleep 5

# ── Wait for connection with retry ────────────────────────────────────────────
CONNECTION_ESTABLISHED=false
for i in $(seq 1 15); do
    TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "azure" | head -1)
    if echo "$TITLE" | grep -qi "localhost.*Azure"; then
        CONNECTION_ESTABLISHED=true
        break
    fi
    if [ "$i" -eq 8 ]; then
        DISPLAY=:1 xdotool key Return
    fi
    sleep 1
done

# ── Retry connection if needed ────────────────────────────────────────────────
if [ "$CONNECTION_ESTABLISHED" = "false" ]; then
    echo "First connection attempt failed, retrying..."
    DISPLAY=:1 xdotool key Escape
    sleep 1
    DISPLAY=:1 xdotool key F1
    sleep 1
    DISPLAY=:1 xdotool type 'new connection'
    sleep 1
    DISPLAY=:1 xdotool key Return
    sleep 2
    DISPLAY=:1 xdotool mousemove 1740 690 click 1; sleep 0.3
    DISPLAY=:1 xdotool key ctrl+a
    DISPLAY=:1 xdotool type 'localhost'; sleep 0.3
    DISPLAY=:1 xdotool mousemove 1740 755 click 1; sleep 0.3
    DISPLAY=:1 xdotool type 'sa'; sleep 0.3
    DISPLAY=:1 xdotool mousemove 1740 785 click 1; sleep 0.3
    DISPLAY=:1 xdotool type 'GymAnything#2024'; sleep 0.3
    DISPLAY=:1 xdotool mousemove 1740 905 click 1; sleep 0.5
    DISPLAY=:1 xdotool key t Return; sleep 0.5
    DISPLAY=:1 xdotool mousemove 1770 1049 click 1
    sleep 8
fi

# ── Open new query editor ─────────────────────────────────────────────────────
DISPLAY=:1 xdotool key F1
sleep 0.5
DISPLAY=:1 xdotool type 'new query'
sleep 0.5
DISPLAY=:1 xdotool key Return
sleep 2

# Clear editor
DISPLAY=:1 xdotool mousemove 600 400 click 1
sleep 0.3
DISPLAY=:1 xdotool key ctrl+a Delete
sleep 0.5

# Final dialog cleanup
DISPLAY=:1 xdotool mousemove 1889 917 click 1   # Close preview X button
sleep 0.5
DISPLAY=:1 xdotool key Escape
sleep 0.5
DISPLAY=:1 xdotool mousemove 960 400 click 1
sleep 0.5

# ── Take initial screenshot ───────────────────────────────────────────────────
take_screenshot /tmp/task_initial.png

echo "=== Setup complete. ADS connected with query editor open. ==="
