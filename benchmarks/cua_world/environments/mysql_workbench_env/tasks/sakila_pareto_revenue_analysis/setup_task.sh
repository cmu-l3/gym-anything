#!/bin/bash
# Setup script for sakila_pareto_revenue_analysis task

echo "=== Setting up Sakila Pareto Revenue Analysis Task ==="

source /workspace/scripts/task_utils.sh

# Fallback for util functions if not loaded
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

# Record task start timestamp (anti-gaming)
date +%s > /tmp/task_start_timestamp

# Ensure MySQL is running
if ! mysqladmin ping -h localhost -u root -p'GymAnything#2024' 2>/dev/null; then
    echo "Starting MySQL service..."
    systemctl start mysql
    sleep 5
fi

# Clean up any previous state
echo "Cleaning up previous views and files..."
mysql -u root -p'GymAnything#2024' sakila -e "
    DROP VIEW IF EXISTS v_pareto_revenue;
    DROP VIEW IF EXISTS v_customer_ltv;
" 2>/dev/null || true

rm -f /home/ga/Documents/exports/vip_whales.csv 2>/dev/null || true
rm -f /tmp/pareto_result.json 2>/dev/null || true

# Ensure directory exists
mkdir -p /home/ga/Documents/exports
chown ga:ga /home/ga/Documents/exports

# Ensure MySQL Workbench is running for the agent
if [ "$(is_workbench_running)" = "false" ]; then
    echo "Starting MySQL Workbench..."
    start_workbench
    sleep 10
fi

# Focus the Workbench window
focus_workbench

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "Agent instructions:"
echo "1. Connect to MySQL (localhost, ga, password123)"
echo "2. Create view v_customer_ltv"
echo "3. Create view v_pareto_revenue with window functions"
echo "4. Export top 80% to /home/ga/Documents/exports/vip_whales.csv"