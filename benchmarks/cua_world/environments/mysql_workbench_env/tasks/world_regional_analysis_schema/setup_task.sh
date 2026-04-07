#!/bin/bash
# Setup script for world_regional_analysis_schema task

echo "=== Setting up World Regional Analysis Schema Task ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions for utilities if not present
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

# Reset state: Drop the target database if it exists from a previous run
echo "Cleaning up previous runs..."
mysql -u root -p'GymAnything#2024' -e "DROP DATABASE IF EXISTS world_regions;" 2>/dev/null || true

# Ensure Source database 'world' exists and is intact
if ! mysql -u root -p'GymAnything#2024' -e "USE world;" 2>/dev/null; then
    echo "Restoring world database..."
    # (Assuming world setup logic is in the environment setup, triggering it if missing)
    if [ -f /tmp/world-db/world.sql ]; then
         mysql -u root -p'GymAnything#2024' < /tmp/world-db/world.sql
    else
        # Fallback quick restore attempt if environment file is missing
        wget -q "https://downloads.mysql.com/docs/world-db.zip" -O /tmp/world-db.zip
        unzip -o /tmp/world-db.zip -d /tmp/
        mysql -u root -p'GymAnything#2024' < /tmp/world-db/world.sql
    fi
fi

# Clean previous export file
rm -f /home/ga/Documents/exports/top20_countries.csv 2>/dev/null || true

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
echo "Agent ready to create world_regions database."