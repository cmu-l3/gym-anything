#!/bin/bash
# Setup script for chinook_encoding_repair
# Creates a corrupted database by introducing encoding artifacts

set -e
echo "=== Setting up Chinook Encoding Repair Task ==="

source /workspace/scripts/task_utils.sh

# Paths
ORIGINAL_DB="/home/ga/Documents/databases/chinook.db"
CORRUPT_DB="/home/ga/Documents/databases/chinook_corrupt.db"
EXPORT_DIR="/home/ga/Documents/exports"
SCRIPTS_DIR="/home/ga/Documents/scripts"

# Ensure directories exist
mkdir -p "$EXPORT_DIR" "$SCRIPTS_DIR"
chown -R ga:ga /home/ga/Documents/

# Remove previous artifacts
rm -f "$CORRUPT_DB"
rm -f "$EXPORT_DIR/repair_summary.csv"
rm -f "$SCRIPTS_DIR/fix_encoding.sql"

# Check source
if [ ! -f "$ORIGINAL_DB" ]; then
    echo "ERROR: Source database not found at $ORIGINAL_DB"
    exit 1
fi

# Create copy to corrupt
echo "Creating corrupt database copy..."
cp "$ORIGINAL_DB" "$CORRUPT_DB"
chown ga:ga "$CORRUPT_DB"

# Function to execute SQL on the corrupt DB
run_sql() {
    sqlite3 "$CORRUPT_DB" "$1"
}

echo "Introducing encoding artifacts..."

# 1. artists.Name
# Replace correct chars with artifacts
run_sql "UPDATE artists SET Name = REPLACE(Name, 'é', 'Ã©');"
run_sql "UPDATE artists SET Name = REPLACE(Name, 'á', 'Ã¡');"
run_sql "UPDATE artists SET Name = REPLACE(Name, 'ã', 'Ã£');"
run_sql "UPDATE artists SET Name = REPLACE(Name, 'ó', 'Ã³');"
run_sql "UPDATE artists SET Name = REPLACE(Name, 'ö', 'Ã¶');"
run_sql "UPDATE artists SET Name = REPLACE(Name, 'ç', 'Ã§');"
run_sql "UPDATE artists SET Name = REPLACE(Name, 'ü', 'Ã¼');"

# 2. tracks.Name and tracks.Composer
for col in "Name" "Composer"; do
    run_sql "UPDATE tracks SET $col = REPLACE($col, 'é', 'Ã©') WHERE $col IS NOT NULL;"
    run_sql "UPDATE tracks SET $col = REPLACE($col, 'á', 'Ã¡') WHERE $col IS NOT NULL;"
    run_sql "UPDATE tracks SET $col = REPLACE($col, 'ã', 'Ã£') WHERE $col IS NOT NULL;"
    run_sql "UPDATE tracks SET $col = REPLACE($col, 'ó', 'Ã³') WHERE $col IS NOT NULL;"
    run_sql "UPDATE tracks SET $col = REPLACE($col, 'ö', 'Ã¶') WHERE $col IS NOT NULL;"
    run_sql "UPDATE tracks SET $col = REPLACE($col, 'ç', 'Ã§') WHERE $col IS NOT NULL;"
    run_sql "UPDATE tracks SET $col = REPLACE($col, 'ü', 'Ã¼') WHERE $col IS NOT NULL;"
done

# 3. customers.FirstName, customers.LastName
for col in "FirstName" "LastName"; do
    run_sql "UPDATE customers SET $col = REPLACE($col, 'é', 'Ã©');"
    run_sql "UPDATE customers SET $col = REPLACE($col, 'á', 'Ã¡');"
    run_sql "UPDATE customers SET $col = REPLACE($col, 'ã', 'Ã£');"
    run_sql "UPDATE customers SET $col = REPLACE($col, 'ó', 'Ã³');"
    run_sql "UPDATE customers SET $col = REPLACE($col, 'ö', 'Ã¶');"
    run_sql "UPDATE customers SET $col = REPLACE($col, 'ç', 'Ã§');"
    run_sql "UPDATE customers SET $col = REPLACE($col, 'ü', 'Ã¼');"
done

# 4. employees.FirstName, employees.LastName
for col in "FirstName" "LastName"; do
    run_sql "UPDATE employees SET $col = REPLACE($col, 'é', 'Ã©');"
    run_sql "UPDATE employees SET $col = REPLACE($col, 'á', 'Ã¡');"
    run_sql "UPDATE employees SET $col = REPLACE($col, 'ã', 'Ã£');"
    run_sql "UPDATE employees SET $col = REPLACE($col, 'ó', 'Ã³');"
    run_sql "UPDATE employees SET $col = REPLACE($col, 'ö', 'Ã¶');"
    run_sql "UPDATE employees SET $col = REPLACE($col, 'ç', 'Ã§');"
    run_sql "UPDATE employees SET $col = REPLACE($col, 'ü', 'Ã¼');"
done

echo "Corruption complete. Verifying presence of artifacts..."

# Count artifacts for verification baseline
ARTIFACT_COUNT=$(sqlite3 "$CORRUPT_DB" "SELECT
    (SELECT COUNT(*) FROM artists WHERE Name LIKE '%Ã%') +
    (SELECT COUNT(*) FROM tracks WHERE Name LIKE '%Ã%' OR Composer LIKE '%Ã%') +
    (SELECT COUNT(*) FROM customers WHERE FirstName LIKE '%Ã%' OR LastName LIKE '%Ã%') +
    (SELECT COUNT(*) FROM employees WHERE FirstName LIKE '%Ã%' OR LastName LIKE '%Ã%');")

echo "Initial artifact count: $ARTIFACT_COUNT"
echo "$ARTIFACT_COUNT" > /tmp/initial_artifact_count

# Record task start time
date +%s > /tmp/task_start_time.txt

# Start DBeaver if not running
if ! is_dbeaver_running; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /usr/share/dbeaver-ce/dbeaver > /tmp/dbeaver.log 2>&1 &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "DBeaver"; then
            break
        fi
        sleep 1
    done
fi

# Focus and maximize DBeaver
focus_dbeaver
DISPLAY=:1 wmctrl -r "DBeaver" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="