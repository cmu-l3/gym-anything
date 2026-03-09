#!/bin/bash
# Setup script for chinook_northwind_market_overlap task
set -e

echo "=== Setting up Market Overlap Task ==="

source /workspace/scripts/task_utils.sh

# Directories
DB_DIR="/home/ga/Documents/databases"
EXPORT_DIR="/home/ga/Documents/exports"
SCRIPTS_DIR="/home/ga/Documents/scripts"

mkdir -p "$DB_DIR" "$EXPORT_DIR" "$SCRIPTS_DIR"
chown -R ga:ga /home/ga/Documents/

# 1. Clean up previous artifacts to ensure fresh run
rm -f "$DB_DIR/market_analysis.db"
rm -f "$EXPORT_DIR/market_overlap_report.csv"
rm -f "$SCRIPTS_DIR/market_analysis.sql"

# 2. Ensure Chinook database exists
CHINOOK_DB="$DB_DIR/chinook.db"
if [ ! -f "$CHINOOK_DB" ]; then
    echo "Restoring Chinook database..."
    if [ -f "/workspace/data/chinook.db" ]; then
        cp "/workspace/data/chinook.db" "$CHINOOK_DB"
    else
        # Fallback download
        wget -q -O "$CHINOOK_DB" "https://github.com/lerocha/chinook-database/raw/master/ChinookDatabase/DataSources/Chinook_Sqlite.sqlite"
    fi
fi
chmod 644 "$CHINOOK_DB"
chown ga:ga "$CHINOOK_DB"

# 3. Ensure Northwind database exists
NORTHWIND_DB="$DB_DIR/northwind.db"
if [ ! -f "$NORTHWIND_DB" ] || [ "$(stat -c%s "$NORTHWIND_DB" 2>/dev/null || echo 0)" -lt 10000 ]; then
    echo "Downloading Northwind database..."
    # Download SQL dump and create DB
    wget -q -O /tmp/northwind.sql "https://raw.githubusercontent.com/jpwhite3/northwind-SQLite3/main/Northwind_large.sql"
    if [ -s /tmp/northwind.sql ]; then
        sqlite3 "$NORTHWIND_DB" < /tmp/northwind.sql
        rm /tmp/northwind.sql
    else
        echo "Failed to download Northwind SQL"
        exit 1
    fi
fi
chmod 644 "$NORTHWIND_DB"
chown ga:ga "$NORTHWIND_DB"

# 4. Verify Source Data Integrity (Basic Checks)
echo "Verifying source data..."
CHINOOK_CUST_COUNT=$(sqlite3 "$CHINOOK_DB" "SELECT COUNT(*) FROM customers;")
NORTHWIND_CUST_COUNT=$(sqlite3 "$NORTHWIND_DB" "SELECT COUNT(*) FROM Customer;")  # Singular 'Customer' in Northwind
echo "Chinook Customers: $CHINOOK_CUST_COUNT"
echo "Northwind Customers: $NORTHWIND_CUST_COUNT"

# 5. Start DBeaver
if ! is_dbeaver_running; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /usr/share/dbeaver-ce/dbeaver > /tmp/dbeaver.log 2>&1 &"
    sleep 10
fi

focus_dbeaver
maximize_window "DBeaver"

# 6. Record timestamp for anti-gaming
date +%s > /tmp/task_start_time

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="