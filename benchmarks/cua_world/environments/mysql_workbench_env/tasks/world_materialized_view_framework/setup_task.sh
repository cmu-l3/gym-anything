#!/bin/bash
# Setup script for world_materialized_view_framework task

echo "=== Setting up World Materialized View Framework Task ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions for local testing if env utils missing
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

# Clean up any previous state to ensure a fresh start
echo "Cleaning up previous objects..."
mysql -u root -p'GymAnything#2024' world -e "
    DROP TABLE IF EXISTS mv_country_stats;
    DROP PROCEDURE IF EXISTS sp_refresh_country_stats;
" 2>/dev/null || true

# Clean previous export
rm -f /home/ga/Documents/exports/country_stats.csv 2>/dev/null || true

# Ensure World database is intact (reload if necessary)
# We check a simple count. If wildly off, we assume corruption and reload.
COUNTRY_COUNT=$(mysql -u root -p'GymAnything#2024' world -N -e "SELECT COUNT(*) FROM country" 2>/dev/null)
if [ "${COUNTRY_COUNT:-0}" -ne 239 ]; then
    echo "World database appears corrupted or missing. Reloading..."
    # Assuming standard setup script location or fallback
    if [ -f "/workspace/scripts/setup_mysql_workbench.sh" ]; then
        /workspace/scripts/setup_mysql_workbench.sh
    fi
fi

# Start Workbench if not running
if [ "$(is_workbench_running)" = "false" ]; then
    echo "Starting MySQL Workbench..."
    start_workbench
fi

focus_workbench

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="