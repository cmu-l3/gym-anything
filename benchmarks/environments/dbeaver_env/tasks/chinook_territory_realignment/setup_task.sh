#!/bin/bash
# Setup script for chinook_territory_realignment
# Prepares the CSV file and ensures DB is in clean initial state

set -e
echo "=== Setting up Chinook Territory Realignment Task ==="

source /workspace/scripts/task_utils.sh

# Directories
DB_DIR="/home/ga/Documents/databases"
DOCS_DIR="/home/ga/Documents"
EXPORT_DIR="/home/ga/Documents/exports"
SCRIPTS_DIR="/home/ga/Documents/scripts"

# Ensure directories exist
mkdir -p "$DB_DIR" "$EXPORT_DIR" "$SCRIPTS_DIR"

# 1. Prepare the Territory Assignment CSV
# This file defines the "New World Order" for sales reps
echo "Creating territory assignment CSV..."
cat > "$DOCS_DIR/territory_assignments.csv" << 'EOF'
Country,RepId
USA,4
Canada,4
Brazil,4
Argentina,4
Chile,4
France,3
Germany,3
United Kingdom,3
Portugal,3
Spain,3
Sweden,3
Ireland,3
Italy,3
Denmark,3
Belgium,3
Austria,3
Poland,3
Norway,3
Hungary,3
Netherlands,3
Czech Republic,3
Finland,3
India,5
Australia,5
EOF
chown ga:ga "$DOCS_DIR/territory_assignments.csv"

# 2. Reset Chinook Database to known state
CHINOOK_DB="$DB_DIR/chinook.db"

# If DB doesn't exist or we want to ensure it's clean, copy from source if available
# The environment setup script usually puts it there, but we ensure permissions
if [ -f "$CHINOOK_DB" ]; then
    # Resetting permissions just in case
    chown ga:ga "$CHINOOK_DB"
    
    # Verify it doesn't already have the target table (in case of re-run)
    sqlite3 "$CHINOOK_DB" "DROP TABLE IF EXISTS territory_map;"
    
    # Record initial check of USA customers (usually Rep 3 in standard Chinook)
    INITIAL_USA_REP=$(sqlite3 "$CHINOOK_DB" "SELECT SupportRepId FROM customers WHERE Country='USA' LIMIT 1;" 2>/dev/null || echo "0")
    echo "$INITIAL_USA_REP" > /tmp/initial_usa_rep
    echo "Initial USA Rep ID: $INITIAL_USA_REP"
else
    echo "ERROR: Chinook database not found at $CHINOOK_DB"
    exit 1
fi

# 3. Clean up previous artifacts
rm -f "$EXPORT_DIR/reassignment_verification.csv"
rm -f "$SCRIPTS_DIR/update_territories.sql"

# 4. Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 5. Launch DBeaver if not running (standard setup)
if ! is_dbeaver_running; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /usr/share/dbeaver-ce/dbeaver > /tmp/dbeaver.log 2>&1 &"
    sleep 10
fi

# Focus and maximize
focus_dbeaver
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 6. Capture initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task Setup Complete ==="
echo "CSV created at: $DOCS_DIR/territory_assignments.csv"