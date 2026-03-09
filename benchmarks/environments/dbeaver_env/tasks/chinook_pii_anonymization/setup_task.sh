#!/bin/bash
# Setup script for chinook_pii_anonymization task
# Prepares a copy of the database and records initial state

set -e
echo "=== Setting up Chinook PII Anonymization Task ==="

source /workspace/scripts/task_utils.sh

# Directories
DB_DIR="/home/ga/Documents/databases"
EXPORT_DIR="/home/ga/Documents/exports"
SCRIPTS_DIR="/home/ga/Documents/scripts"
SOURCE_DB="$DB_DIR/chinook.db"
TARGET_DB="$DB_DIR/chinook_vendor.db"

# Ensure directories exist
mkdir -p "$DB_DIR" "$EXPORT_DIR" "$SCRIPTS_DIR"
chown -R ga:ga /home/ga/Documents/

# Clean up previous runs
rm -f "$TARGET_DB"
rm -f "$EXPORT_DIR/anonymization_report.csv"
rm -f "$SCRIPTS_DIR/anonymize_customers.sql"

# Check source DB
if [ ! -f "$SOURCE_DB" ]; then
    echo "Downloading Chinook database..."
    wget -q -O "$SOURCE_DB" "https://github.com/lerocha/chinook-database/raw/master/ChinookDatabase/DataSources/Chinook_Sqlite.sqlite"
fi

# Create the specific vendor DB copy for this task
echo "Creating vendor database copy..."
cp "$SOURCE_DB" "$TARGET_DB"
chown ga:ga "$TARGET_DB"

# Record initial state for anti-gaming (capture a specific real name to ensure it changes)
# Customer 1 is usually "Luís Gonçalves"
INITIAL_NAME=$(sqlite3 "$TARGET_DB" "SELECT FirstName || ' ' || LastName FROM customers WHERE CustomerId=1;")
echo "$INITIAL_NAME" > /tmp/initial_customer_1_name.txt

# Record initial NULL count for Company to verify logic later
# Count how many are NOT NULL initially (these should become 'REDACTED')
INITIAL_NOT_NULL_COMPANIES=$(sqlite3 "$TARGET_DB" "SELECT COUNT(*) FROM customers WHERE Company IS NOT NULL;")
echo "$INITIAL_NOT_NULL_COMPANIES" > /tmp/initial_not_null_companies.txt

# Start DBeaver if not running
if ! is_dbeaver_running; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /usr/share/dbeaver-ce/dbeaver > /tmp/dbeaver.log 2>&1 &"
    sleep 10
fi

# Focus DBeaver
focus_dbeaver
DISPLAY=:1 wmctrl -r "DBeaver" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_timestamp

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Target Database: $TARGET_DB"