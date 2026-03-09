#!/bin/bash
# Setup script for sakila_bi_analytics task

echo "=== Setting up Sakila BI Analytics Task ==="

source /workspace/scripts/task_utils.sh

if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type is_mysql_running &>/dev/null; then
    is_mysql_running() { mysqladmin ping -h localhost -u root -p'GymAnything#2024' 2>/dev/null && echo "true" || echo "false"; }
fi
if ! type start_workbench &>/dev/null; then
    start_workbench() { su - ga -c "DISPLAY=:1 /snap/bin/mysql-workbench-community > /tmp/mysql-workbench.log 2>&1 &"; sleep 10; }
fi
if ! type is_workbench_running &>/dev/null; then
    is_workbench_running() { pgrep -f "mysql-workbench" > /dev/null 2>&1 && echo "true" || echo "false"; }
fi
if ! type focus_workbench &>/dev/null; then
    focus_workbench() { local wid=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "workbench\|mysql" | head -1 | awk '{print $1}'); [ -n "$wid" ] && DISPLAY=:1 wmctrl -ia "$wid" 2>/dev/null || true; }
fi

date +%s > /tmp/task_start_timestamp

if [ "$(is_mysql_running)" = "false" ]; then
    echo "Starting MySQL..."
    systemctl start mysql
    sleep 5
fi

# Drop pre-existing views/users from previous runs
echo "Cleaning previous state..."
mysql -u root -p'GymAnything#2024' sakila -e "
    DROP VIEW IF EXISTS v_film_revenue_by_store;
    DROP VIEW IF EXISTS v_customer_lifetime_value;
" 2>/dev/null || true

# Remove reporter user if exists
mysql -u root -p'GymAnything#2024' -e "
    DROP USER IF EXISTS 'reporter'@'localhost';
" 2>/dev/null || true

# Record baseline (should all be 0)
VIEW1_COUNT=$(mysql -u root -p'GymAnything#2024' information_schema -N -e "
    SELECT COUNT(*) FROM VIEWS WHERE TABLE_SCHEMA='sakila' AND TABLE_NAME='v_film_revenue_by_store'
" 2>/dev/null)
VIEW2_COUNT=$(mysql -u root -p'GymAnything#2024' information_schema -N -e "
    SELECT COUNT(*) FROM VIEWS WHERE TABLE_SCHEMA='sakila' AND TABLE_NAME='v_customer_lifetime_value'
" 2>/dev/null)
USER_COUNT=$(mysql -u root -p'GymAnything#2024' -N -e "
    SELECT COUNT(*) FROM mysql.user WHERE User='reporter' AND Host='localhost'
" 2>/dev/null)

echo "${VIEW1_COUNT:-0}" > /tmp/initial_view1_count
echo "${VIEW2_COUNT:-0}" > /tmp/initial_view2_count
echo "${USER_COUNT:-0}" > /tmp/initial_user_count

echo "Baseline: view1=${VIEW1_COUNT:-0} view2=${VIEW2_COUNT:-0} user=${USER_COUNT:-0}"

# Verify Sakila has expected data
CUSTOMER_COUNT=$(mysql -u root -p'GymAnything#2024' sakila -N -e "SELECT COUNT(*) FROM customer;" 2>/dev/null)
echo "Sakila customers: ${CUSTOMER_COUNT:-0}"

# Clean previous export
rm -f /home/ga/Documents/exports/customer_lifetime_value.csv 2>/dev/null || true

if [ "$(is_workbench_running)" = "false" ]; then
    start_workbench
    sleep 10
fi
focus_workbench

take_screenshot /tmp/task_start_screenshot.png
echo "=== Setup Complete ==="
echo "Agent must create 2 views, 1 user, grant privileges, and export CSV."
