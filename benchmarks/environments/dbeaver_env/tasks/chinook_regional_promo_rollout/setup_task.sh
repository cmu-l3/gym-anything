#!/bin/bash
# Setup for chinook_regional_promo_rollout
set -e
echo "=== Setting up Chinook Regional Promo Rollout Task ==="

source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# Database paths
DB_DIR="/home/ga/Documents/databases"
CHINOOK_DB="$DB_DIR/chinook.db"
EXPORT_DIR="/home/ga/Documents/exports"

# Ensure clean state
mkdir -p "$EXPORT_DIR"
mkdir -p "$DB_DIR"

# Force fresh copy of Chinook to ensure no previous attempts persist
# The env setup puts a copy at $CHINOOK_DB, but we overwrite to be safe if it exists from previous runs
if [ -f "/workspace/data/chinook.db" ]; then
    cp /workspace/data/chinook.db "$CHINOOK_DB"
elif [ -f "/tmp/chinook.db" ]; then
    cp /tmp/chinook.db "$CHINOOK_DB"
fi
chmod 666 "$CHINOOK_DB"
chown ga:ga "$CHINOOK_DB"

# Remove any existing report
rm -f "$EXPORT_DIR/promo_impact_analysis.csv"

# Record initial row count (should be 412 invoices standard)
INITIAL_INVOICES=$(sqlite3 "$CHINOOK_DB" "SELECT COUNT(*) FROM invoices;" 2>/dev/null || echo "0")
echo "$INITIAL_INVOICES" > /tmp/initial_invoice_count.txt

# Ensure DBeaver is running
if ! is_dbeaver_running; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /usr/share/dbeaver-ce/dbeaver > /tmp/dbeaver.log 2>&1 &"
    sleep 10
fi

# Focus and maximize
focus_dbeaver
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Capture initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="