#!/bin/bash
# Setup script for chinook_daily_revenue_gaps
# Prepares the environment and calculates ground truth data

set -e
echo "=== Setting up Chinook Daily Revenue Gap Analysis ==="

source /workspace/scripts/task_utils.sh

# Directories
DB_PATH="/home/ga/Documents/databases/chinook.db"
EXPORT_DIR="/home/ga/Documents/exports"
SCRIPTS_DIR="/home/ga/Documents/scripts"

# Ensure directories exist
mkdir -p "$EXPORT_DIR" "$SCRIPTS_DIR"
chown -R ga:ga /home/ga/Documents

# Clean up previous runs
rm -f "$EXPORT_DIR/daily_revenue_2012.csv"
rm -f "$SCRIPTS_DIR/date_gap_analysis.sql"

# Ensure DBeaver is running
if ! is_dbeaver_running; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /usr/share/dbeaver-ce/dbeaver > /tmp/dbeaver.log 2>&1 &"
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -qi "dbeaver"; then
            break
        fi
        sleep 1
    done
    sleep 5
fi

# Focus and maximize DBeaver
focus_dbeaver
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Calculate Ground Truth values from the database
# We need the total revenue for 2012 to verify the agent's aggregation didn't lose or duplicate data
echo "Calculating ground truth..."
GT_TOTAL_REVENUE=$(sqlite3 "$DB_PATH" "SELECT SUM(Total) FROM invoices WHERE strftime('%Y', InvoiceDate) = '2012';" 2>/dev/null || echo "0")
echo "Ground Truth 2012 Revenue: $GT_TOTAL_REVENUE" > /tmp/gt_total_revenue.txt

# Record task start time
date +%s > /tmp/task_start_time.txt

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="