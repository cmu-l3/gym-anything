#!/bin/bash
# Setup for production_capacity_bottleneck task

set -e
echo "=== Setting up Production Capacity Bottleneck Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create export directory with proper permissions
mkdir -p /home/ga/Documents/exports
chown -R ga:ga /home/ga/Documents
rm -f /home/ga/Documents/exports/bottleneck_report_2013.csv

# Ensure SQL Server is ready
if ! mssql_is_running; then
    echo "ERROR: SQL Server is not running"
    exit 1
fi

# Clean up any existing objects from previous runs to ensure a fresh start
echo "Cleaning up database objects..."
mssql_query "
    USE AdventureWorks2022;
    DROP PROCEDURE IF EXISTS dbo.usp_IdentifyBottlenecks;
    DROP TABLE IF EXISTS Production.BottleneckAnalysis;
    DROP VIEW IF EXISTS dbo.vw_WorkCenterMonthlyMetrics;
    DROP FUNCTION IF EXISTS dbo.fn_UtilizationRate;
" "AdventureWorks2022" 2>/dev/null || true

# Record initial state
mssql_count "Production.WorkOrderRouting" > /tmp/initial_routing_count.txt
echo "Initial WorkOrderRouting count: $(cat /tmp/initial_routing_count.txt)"

# Ensure Azure Data Studio is running and configured
echo "Configuring Azure Data Studio..."
if ! ads_is_running; then
    # Launch ADS as user ga
    su - ga -c "DISPLAY=:1 /snap/bin/azuredatastudio > /tmp/ads.log 2>&1 &"
    
    # Wait for window
    for i in {1..45}; do
        if DISPLAY=:1 wmctrl -l | grep -i "azure\|data studio"; then
            echo "ADS window detected"
            break
        fi
        sleep 1
    done
fi

# Maximize ADS window
sleep 2
DISPLAY=:1 wmctrl -r "Azure Data Studio" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -r "data studio" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus window
DISPLAY=:1 wmctrl -a "Azure Data Studio" 2>/dev/null || true

# Dismiss common startup dialogs if they appear
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="