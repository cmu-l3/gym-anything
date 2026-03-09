#!/bin/bash
# Setup script for chinook_payroll_etl task
set -e

echo "=== Setting up Chinook Payroll ETL Task ==="

source /workspace/scripts/task_utils.sh

# Define paths
DB_DIR="/home/ga/Documents/databases"
SCRIPTS_DIR="/home/ga/Documents/scripts"
CHINOOK_DB="$DB_DIR/chinook.db"
PAYROLL_DB="$DB_DIR/payroll.db"

# Ensure directories exist
mkdir -p "$DB_DIR" "$SCRIPTS_DIR"

# Check if Chinook exists (it should be there from env setup, but ensure it)
if [ ! -f "$CHINOOK_DB" ]; then
    echo "Restoring Chinook database..."
    cp /workspace/data/chinook.db "$CHINOOK_DB" 2>/dev/null || \
    wget -q -O "$CHINOOK_DB" "https://github.com/lerocha/chinook-database/raw/master/ChinookDatabase/DataSources/Chinook_Sqlite.sqlite"
fi

# Create an empty SQLite database for Payroll
echo "Creating empty Payroll database..."
rm -f "$PAYROLL_DB"
touch "$PAYROLL_DB"
sqlite3 "$PAYROLL_DB" "VACUUM;" # Initializes valid SQLite header
chmod 666 "$PAYROLL_DB"

# Clean up previous scripts
rm -f "$SCRIPTS_DIR/calculate_commissions.sql"

# Set permissions
chown -R ga:ga /home/ga/Documents

# Record task start time
date +%s > /tmp/task_start_time.txt

# Start DBeaver
if ! is_dbeaver_running; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /usr/share/dbeaver-ce/dbeaver > /tmp/dbeaver.log 2>&1 &"
    # Wait for start
    sleep 15
fi

# Focus DBeaver
focus_dbeaver

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Source: $CHINOOK_DB"
echo "Target: $PAYROLL_DB"