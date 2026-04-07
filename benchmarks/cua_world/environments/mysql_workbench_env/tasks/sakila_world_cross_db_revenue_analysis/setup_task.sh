#!/bin/bash
# Setup script for sakila_world_cross_db_revenue_analysis task

echo "=== Setting up Sakila-World Cross-DB Analysis Task ==="

source /workspace/scripts/task_utils.sh

# 1. Define fallback utility functions if not present
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

# 2. Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_timestamp

# 3. Ensure MySQL is running
if [ "$(is_mysql_running)" = "false" ]; then
    echo "Starting MySQL service..."
    systemctl start mysql
    sleep 5
fi

# 4. Ensure Databases Exist (Sakila and World)
# The environment setup usually installs these, but we verify here.
echo "Verifying databases..."
DBS=$(mysql -u root -p'GymAnything#2024' -N -e "SHOW DATABASES LIKE 'sakila'; SHOW DATABASES LIKE 'world';")
if [[ "$DBS" != *"sakila"* ]] || [[ "$DBS" != *"world"* ]]; then
    echo "WARNING: Required databases missing. Attempting to reload..."
    # Attempt to run the post_start hook logic if strictly needed,
    # but for now we assume the base env is correct.
    # In a real scenario, we might trigger a restore script here.
fi

# 5. Clean up any previous task artifacts (Clean Slate)
echo "Cleaning up previous attempts..."
mysql -u root -p'GymAnything#2024' -e "
    DROP TABLE IF EXISTS sakila.country_xref;
    DROP VIEW IF EXISTS sakila.v_revenue_demographics;
    DROP PROCEDURE IF EXISTS sakila.sp_continent_report;
" 2>/dev/null || true

# Remove export files
rm -f /home/ga/Documents/exports/asia_revenue_report.csv 2>/dev/null || true
rm -f /home/ga/Documents/exports/revenue_per_capita_ranking.csv 2>/dev/null || true

# 6. Ensure MySQL Workbench is running and focused
if [ "$(is_workbench_running)" = "false" ]; then
    echo "Starting MySQL Workbench..."
    start_workbench
    sleep 5
fi

echo "Focusing Workbench..."
focus_workbench
# Maximize window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "workbench\|mysql" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="