#!/bin/bash
# Setup script for sakila_temporal_gap_filling_reporting task

echo "=== Setting up Sakila Temporal Gap Filling Task ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions for utilities
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type is_workbench_running &>/dev/null; then
    is_workbench_running() { pgrep -f "mysql-workbench" > /dev/null 2>&1 && echo "true" || echo "false"; }
fi
if ! type start_workbench &>/dev/null; then
    start_workbench() { su - ga -c "DISPLAY=:1 /snap/bin/mysql-workbench-community > /tmp/mysql-workbench.log 2>&1 &"; sleep 10; }
fi
if ! type focus_workbench &>/dev/null; then
    focus_workbench() { local wid=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "workbench\|mysql" | head -1 | awk '{print $1}'); [ -n "$wid" ] && DISPLAY=:1 wmctrl -ia "$wid" 2>/dev/null || true; }
fi

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Ensure MySQL is running
if ! mysqladmin ping -h localhost -u root -p'GymAnything#2024' 2>/dev/null; then
    echo "Starting MySQL service..."
    systemctl start mysql
    sleep 5
fi

# 1. Reset Sakila database to ensure clean state
echo "Resetting Sakila data..."
# (Assuming Sakila is already installed by environment, but we ensure the gaps are created cleanly)

# 2. Simulate System Outage: Delete data for specific dates
echo "Creating data gaps for July 4th and July 15th, 2005..."
mysql -u root -p'GymAnything#2024' sakila -e "
    DELETE FROM payment WHERE DATE(payment_date) = '2005-07-04';
    DELETE FROM payment WHERE DATE(payment_date) = '2005-07-15';
" 2>/dev/null

# Verify gaps exist
GAP_CHECK=$(mysql -u root -p'GymAnything#2024' sakila -N -e "
    SELECT COUNT(*) FROM payment 
    WHERE DATE(payment_date) IN ('2005-07-04', '2005-07-15');
" 2>/dev/null)

if [ "$GAP_CHECK" -eq 0 ]; then
    echo "Data gaps created successfully."
else
    echo "WARNING: Failed to create data gaps. Count: $GAP_CHECK"
fi

# 3. Clean up any previous views or exports
mysql -u root -p'GymAnything#2024' sakila -e "
    DROP VIEW IF EXISTS v_july_2005_calendar;
    DROP VIEW IF EXISTS v_july_revenue_analysis;
" 2>/dev/null || true

rm -f /home/ga/Documents/exports/july_revenue_continuous.csv 2>/dev/null || true
rm -f /home/ga/Documents/exports/zero_revenue_days.csv 2>/dev/null || true
rm -f /tmp/gap_analysis_result.json 2>/dev/null || true

# 4. Ensure Workbench is ready
if [ "$(is_workbench_running)" = "false" ]; then
    echo "Starting MySQL Workbench..."
    start_workbench
else
    echo "MySQL Workbench already running."
fi

focus_workbench

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Gaps created: 2005-07-04 and 2005-07-15 have 0 payments."