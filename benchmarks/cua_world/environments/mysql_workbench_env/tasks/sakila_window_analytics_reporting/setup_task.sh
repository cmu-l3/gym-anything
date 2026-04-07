#!/bin/bash
# Setup script for sakila_window_analytics_reporting

echo "=== Setting up Sakila Window Analytics Reporting Task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure MySQL is running
if ! mysqladmin ping -h localhost -u root -p'GymAnything#2024' 2>/dev/null; then
    echo "Starting MySQL service..."
    systemctl start mysql
    sleep 5
fi

# Clean up any pre-existing objects from previous attempts to ensure a clean slate
echo "Cleaning up pre-existing objects..."
mysql -u root -p'GymAnything#2024' sakila -e "
    DROP VIEW IF EXISTS v_film_revenue_ranked;
    DROP VIEW IF EXISTS v_customer_rfm;
    DROP TABLE IF EXISTS rpt_monthly_category_performance;
    DROP PROCEDURE IF EXISTS sp_refresh_category_performance;
" 2>/dev/null || true

# Verify Sakila database is loaded and has data
FILM_COUNT=$(mysql -u root -p'GymAnything#2024' sakila -N -e "SELECT COUNT(*) FROM film;" 2>/dev/null || echo "0")
if [ "$FILM_COUNT" -lt 900 ]; then
    echo "Sakila database seems empty (count=$FILM_COUNT). Attempting reload..."
    if [ -f "/tmp/sakila-db/sakila-schema.sql" ]; then
        mysql -u root -p'GymAnything#2024' < /tmp/sakila-db/sakila-schema.sql 2>/dev/null || true
        mysql -u root -p'GymAnything#2024' < /tmp/sakila-db/sakila-data.sql 2>/dev/null || true
    fi
fi

# Create export directory and clean old files
mkdir -p /home/ga/Documents/exports
rm -f /home/ga/Documents/exports/film_revenue_ranked.csv
rm -f /home/ga/Documents/exports/monthly_category_performance.csv
chown -R ga:ga /home/ga/Documents/exports

# Ensure MySQL Workbench is running for the agent
if ! pgrep -f "mysql-workbench" > /dev/null 2>&1; then
    echo "Starting MySQL Workbench..."
    su - ga -c "DISPLAY=:1 /snap/bin/mysql-workbench-community > /tmp/mysql-workbench.log 2>&1 &"
    sleep 10
fi

# Wait for window and maximize
WORKBENCH_READY=false
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "workbench\|mysql"; then
        WORKBENCH_READY=true
        break
    fi
    sleep 1
done

if [ "$WORKBENCH_READY" = true ]; then
    sleep 2
    # Get Window ID
    WID=$(DISPLAY=:1 wmctrl -l | grep -i "workbench\|mysql" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi
    # Dismiss any random dialogs (e.g. "Welcome")
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
fi

# Take initial state screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="