#!/bin/bash
set -e
echo "=== Setting up sakila_crosstab_rental_reports task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure MySQL is running
if ! mysqladmin ping -h localhost -u root -p'GymAnything#2024' 2>/dev/null; then
    echo "Starting MySQL service..."
    systemctl start mysql
    sleep 5
fi

# Clean up any previous attempts (drop views, remove files)
echo "Cleaning up previous state..."
mysql -u root -p'GymAnything#2024' sakila -e "
    DROP VIEW IF EXISTS v_rental_by_day_category;
    DROP VIEW IF EXISTS v_monthly_rental_trend;
    DROP VIEW IF EXISTS v_rating_revenue_matrix;
" 2>/dev/null || true

rm -f /home/ga/Documents/exports/rental_by_day_category.csv 2>/dev/null || true
rm -f /home/ga/Documents/exports/rating_revenue_matrix.csv 2>/dev/null || true
mkdir -p /home/ga/Documents/exports
chown -R ga:ga /home/ga/Documents

# Ensure MySQL Workbench is running and visible
if ! pgrep -f "mysql-workbench" > /dev/null 2>&1; then
    echo "Starting MySQL Workbench..."
    su - ga -c "DISPLAY=:1 /snap/bin/mysql-workbench-community > /tmp/mysql-workbench.log 2>&1 &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "workbench\|mysql"; then
            echo "Workbench window detected"
            break
        fi
        sleep 1
    done
fi

# Maximize and focus
WID=$(DISPLAY=:1 wmctrl -l | grep -i "workbench\|mysql" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Dismiss any potential dialogs
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Record initial counts
RENTAL_COUNT=$(mysql -u ga -ppassword123 sakila -N -e "SELECT COUNT(*) FROM rental;" 2>/dev/null || echo "0")
echo "$RENTAL_COUNT" > /tmp/initial_rental_count.txt

# Capture initial screenshot
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="