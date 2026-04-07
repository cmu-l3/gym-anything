#!/bin/bash
# Setup script for Sakila RFM Segmentation Task

echo "=== Setting up Sakila RFM Segmentation Task ==="

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

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# Ensure MySQL is running
if ! mysqladmin ping -h localhost -u root -p'GymAnything#2024' 2>/dev/null; then
    echo "Starting MySQL service..."
    systemctl start mysql
    sleep 5
fi

# Clean state: Drop the target table if it exists (from previous runs)
echo "Cleaning database state..."
mysql -u root -p'GymAnything#2024' sakila -e "DROP TABLE IF EXISTS customer_rfm_scores;" 2>/dev/null || true

# Clean artifacts: Remove previous export files
echo "Cleaning artifacts..."
rm -f /home/ga/Documents/exports/churn_risk_customers.csv 2>/dev/null || true
mkdir -p /home/ga/Documents/exports
chown ga:ga /home/ga/Documents/exports

# Ensure Workbench is open for the agent
if [ "$(is_workbench_running)" = "false" ]; then
    echo "Starting MySQL Workbench..."
    start_workbench
else
    echo "MySQL Workbench is already running."
fi

# Focus and maximize
focus_workbench
DISPLAY=:1 wmctrl -r "MySQL Workbench" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Reference Date for RFM: 2006-02-14 23:59:59"