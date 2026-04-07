#!/bin/bash
# Setup script for sakila_visual_model_evolution task

echo "=== Setting up Sakila Visual Model Evolution Task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming checks
date +%s > /tmp/task_start_timestamp

# Ensure MySQL is running
if [ "$(is_mysql_running)" = "false" ]; then
    echo "Starting MySQL service..."
    systemctl start mysql
    sleep 5
fi

# Ensure Sakila database exists
if ! mysql -u ga -ppassword123 -e "USE sakila;" 2>/dev/null; then
    echo "Restoring Sakila database..."
    # Re-run the setup logic if sakila is missing (unlikely given env setup, but good for robustness)
    /workspace/scripts/setup_mysql_workbench.sh
fi

# Clean up previous state: Drop the target table if it exists
echo "Cleaning up database state..."
mysql -u ga -ppassword123 sakila -e "DROP TABLE IF EXISTS customer_tier_history;" 2>/dev/null

# Clean up previous model files
rm -f /home/ga/Documents/sakila_loyalty_model.mwb 2>/dev/null

# Ensure MySQL Workbench is running and ready
if [ "$(is_workbench_running)" = "false" ]; then
    echo "Starting MySQL Workbench..."
    start_workbench
    sleep 10
fi

# Focus and maximize Workbench
focus_workbench
# Ensure it's maximized
WID=$(get_workbench_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot for evidence
take_screenshot /tmp/task_start_screenshot.png

# Clear any previous result files
rm -f /tmp/model_evolution_result.json 2>/dev/null || true

echo "=== Task setup complete ==="
echo "State prepared: Sakila DB present, 'customer_tier_history' table removed, Workbench running."