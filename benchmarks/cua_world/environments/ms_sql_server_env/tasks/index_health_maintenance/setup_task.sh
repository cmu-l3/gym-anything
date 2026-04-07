#!/bin/bash
# Setup for index_health_maintenance task
echo "=== Setting up Index Health Maintenance Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create exports directory
mkdir -p /home/ga/Documents/exports
chown -R ga:ga /home/ga/Documents/exports
rm -f /home/ga/Documents/exports/index_maintenance.sql

# ============================================================
# Clean up previous state
# ============================================================
echo "Cleaning up previous task artifacts..."
mssql_query "
    IF OBJECT_ID('DBAMaintenance.usp_AnalyzeIndexHealth', 'P') IS NOT NULL DROP PROCEDURE DBAMaintenance.usp_AnalyzeIndexHealth;
    IF OBJECT_ID('DBAMaintenance.usp_DetectOverlappingIndexes', 'P') IS NOT NULL DROP PROCEDURE DBAMaintenance.usp_DetectOverlappingIndexes;
    IF OBJECT_ID('DBAMaintenance.IndexHealthReport', 'U') IS NOT NULL DROP TABLE DBAMaintenance.IndexHealthReport;
    IF OBJECT_ID('DBAMaintenance.OverlappingIndexes', 'U') IS NOT NULL DROP TABLE DBAMaintenance.OverlappingIndexes;
    IF EXISTS (SELECT * FROM sys.schemas WHERE name = 'DBAMaintenance') DROP SCHEMA DBAMaintenance;
" "AdventureWorks2022" || true

# ============================================================
# Record initial DB state (Index counts)
# ============================================================
INDEX_COUNT=$(mssql_query "SELECT COUNT(*) FROM sys.indexes WHERE type_desc != 'HEAP'" "AdventureWorks2022" | tr -d ' \r\n')
echo "$INDEX_COUNT" > /tmp/initial_index_count.txt
echo "Initial non-heap index count: $INDEX_COUNT"

# ============================================================
# Ensure Azure Data Studio is running
# ============================================================
echo "Ensuring Azure Data Studio is running..."

ADS_RUNNING=false
if pgrep -f "azuredatastudio" > /dev/null 2>&1; then
    ADS_RUNNING=true
    echo "Azure Data Studio is already running"
fi

if [ "$ADS_RUNNING" = false ]; then
    echo "Launching Azure Data Studio..."
    ADS_CMD="/snap/bin/azuredatastudio"
    [ ! -x "$ADS_CMD" ] && ADS_CMD="azuredatastudio"
    
    su - ga -c "DISPLAY=:1 $ADS_CMD > /tmp/ads_launch.log 2>&1 &"

    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "azure\|data studio"; then
            echo "Azure Data Studio window detected"
            break
        fi
        sleep 1
    done
fi

sleep 5

# Maximize and focus
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "azure\|data studio" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Dismiss dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Connect to SQL Server (helper to ensure connection panel is ready)
# We assume the agent will connect, but we can prep the environment
# by ensuring the window is active.
DISPLAY=:1 xdotool mousemove 960 540 click 1

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="