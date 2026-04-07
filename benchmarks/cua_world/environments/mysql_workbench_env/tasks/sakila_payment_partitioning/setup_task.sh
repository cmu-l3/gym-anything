#!/bin/bash
# Setup script for sakila_payment_partitioning task

echo "=== Setting up Sakila Payment Partitioning Task ==="

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

# Clean up previous state to ensure clean start
echo "Cleaning up previous run artifacts..."
mysql -u root -p'GymAnything#2024' sakila -e "
    DROP TABLE IF EXISTS payment_archive;
    DROP PROCEDURE IF EXISTS sp_partition_stats;
" 2>/dev/null || true

# Remove export file
rm -f /home/ga/Documents/exports/partition_stats.csv 2>/dev/null || true

# Ensure Sakila payment table exists and has data (integrity check)
PAYMENT_COUNT=$(mysql -u root -p'GymAnything#2024' sakila -N -e "SELECT COUNT(*) FROM payment" 2>/dev/null)
echo "Current payment records: ${PAYMENT_COUNT:-0}"
echo "${PAYMENT_COUNT:-0}" > /tmp/initial_payment_count

# Ensure MySQL Workbench is running
if [ "$(is_workbench_running)" = "false" ]; then
    echo "Starting MySQL Workbench..."
    start_workbench
else
    echo "MySQL Workbench is already running"
fi

# Focus the window
focus_workbench

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task Setup Complete ==="