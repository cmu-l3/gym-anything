#!/bin/bash
# Setup script for sakila_personalized_recommendations_engine

echo "=== Setting up Sakila Recommendations Task ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions if utils not present
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

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# Ensure MySQL is running
if ! mysqladmin ping -h localhost -u root -p'GymAnything#2024' 2>/dev/null; then
    echo "Starting MySQL service..."
    systemctl start mysql
    sleep 5
fi

# Reset state: Drop table and procedure if they exist from previous runs
echo "Cleaning up previous state..."
mysql -u root -p'GymAnything#2024' sakila -e "
    DROP TABLE IF EXISTS customer_recommendations;
    DROP PROCEDURE IF EXISTS sp_generate_recommendations;
" 2>/dev/null || true

# Remove previous export
rm -f /home/ga/Documents/exports/recommendations_batch_01.csv 2>/dev/null || true

# Ensure MySQL Workbench is running (Task setup requirement)
if [ "$(is_workbench_running)" = "false" ]; then
    echo "Starting MySQL Workbench..."
    start_workbench
fi

# Focus the Workbench window
focus_workbench

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "State reset: customer_recommendations dropped, previous exports removed."