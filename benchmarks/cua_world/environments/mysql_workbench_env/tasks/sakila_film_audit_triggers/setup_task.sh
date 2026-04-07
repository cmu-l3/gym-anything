#!/bin/bash
# Setup script for sakila_film_audit_triggers task

echo "=== Setting up Sakila Film Audit Triggers Task ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions for utilities if not present
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
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

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# Ensure MySQL is running
if ! mysqladmin ping -h localhost -u root -p'GymAnything#2024' 2>/dev/null; then
    echo "Starting MySQL service..."
    systemctl start mysql
    sleep 5
fi

echo "Cleaning up previous state..."

# Reset Sakila film table data (specifically film_id 1 which is modified in the task)
mysql -u root -p'GymAnything#2024' sakila -e "
    UPDATE film SET rental_rate = 0.99 WHERE film_id = 1;
" 2>/dev/null

# Remove any existing audit table and triggers from previous runs
mysql -u root -p'GymAnything#2024' sakila -e "
    DROP TABLE IF EXISTS film_audit_log;
    DROP TRIGGER IF EXISTS trg_film_after_insert;
    DROP TRIGGER IF EXISTS trg_film_after_update;
    DROP TRIGGER IF EXISTS trg_film_after_delete;
    DELETE FROM film WHERE title = 'AUDIT TEST FILM';
" 2>/dev/null || true

# Clean previous export file
rm -f /home/ga/Documents/exports/film_audit_log.csv 2>/dev/null || true

# Ensure MySQL Workbench is running
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