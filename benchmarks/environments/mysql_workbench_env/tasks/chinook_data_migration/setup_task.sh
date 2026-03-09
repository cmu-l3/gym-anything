#!/bin/bash
# Setup script for chinook_data_migration task

echo "=== Setting up Chinook Data Migration Task ==="

source /workspace/scripts/task_utils.sh

if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type is_mysql_running &>/dev/null; then
    is_mysql_running() { mysqladmin ping -h localhost -u root -p'GymAnything#2024' 2>/dev/null && echo "true" || echo "false"; }
fi
if ! type start_workbench &>/dev/null; then
    start_workbench() { su - ga -c "DISPLAY=:1 /snap/bin/mysql-workbench-community > /tmp/mysql-workbench.log 2>&1 &"; sleep 10; }
fi
if ! type is_workbench_running &>/dev/null; then
    is_workbench_running() { pgrep -f "mysql-workbench" > /dev/null 2>&1 && echo "true" || echo "false"; }
fi
if ! type focus_workbench &>/dev/null; then
    focus_workbench() { local wid=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "workbench\|mysql" | head -1 | awk '{print $1}'); [ -n "$wid" ] && DISPLAY=:1 wmctrl -ia "$wid" 2>/dev/null || true; }
fi

date +%s > /tmp/task_start_timestamp

if [ "$(is_mysql_running)" = "false" ]; then
    echo "Starting MySQL..."
    systemctl start mysql
    sleep 5
fi

# Download and load Chinook database (real digital music store dataset)
echo "Downloading Chinook database..."
CHINOOK_SQL="/tmp/chinook.sql"

if [ ! -s "$CHINOOK_SQL" ]; then
    wget -q --timeout=60 \
        "https://raw.githubusercontent.com/lerocha/chinook-database/master/ChinookDatabase/DataSources/Chinook_MySql_AutoIncrementPKs.sql" \
        -O "$CHINOOK_SQL" 2>/dev/null
fi

if [ ! -s "$CHINOOK_SQL" ]; then
    # Fallback mirror
    wget -q --timeout=60 \
        "https://github.com/lerocha/chinook-database/releases/download/v1.4.5/Chinook_MySql_AutoIncrementPKs.sql" \
        -O "$CHINOOK_SQL" 2>/dev/null
fi

if [ ! -s "$CHINOOK_SQL" ]; then
    echo "ERROR: Could not download Chinook database. Task requires network connectivity to GitHub."
    echo "Please check network and retry."
    exit 1
fi

echo "Chinook SQL downloaded ($(wc -c < "$CHINOOK_SQL") bytes). Loading..."

# Replace "Chinook" with "chinook" (lowercase) for consistency
sed -i 's/`Chinook`/`chinook`/g' "$CHINOOK_SQL"

# Drop and recreate database
mysql -u root -p'GymAnything#2024' -e "DROP DATABASE IF EXISTS chinook;" 2>/dev/null || true
mysql -u root -p'GymAnything#2024' < "$CHINOOK_SQL" 2>/dev/null

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to load Chinook database."
    exit 1
fi

# Verify load
INVOICE_COUNT=$(mysql -u root -p'GymAnything#2024' chinook -N -e "SELECT COUNT(*) FROM Invoice;" 2>/dev/null)
echo "Chinook loaded: ${INVOICE_COUNT:-0} invoices"

if [ "${INVOICE_COUNT:-0}" -lt 100 ]; then
    echo "ERROR: Chinook database did not load correctly (too few invoices)."
    exit 1
fi

# Grant privileges to ga user
mysql -u root -p'GymAnything#2024' -e "
    GRANT ALL PRIVILEGES ON chinook.* TO 'ga'@'localhost';
    FLUSH PRIVILEGES;
" 2>/dev/null

# Drop any pre-existing view/index from previous runs
mysql -u root -p'GymAnything#2024' chinook -e "
    DROP VIEW IF EXISTS v_sales_by_genre;
    DROP INDEX IF EXISTS idx_invoiceline_trackid ON InvoiceLine;
" 2>/dev/null || true

# Record baseline
echo "0" > /tmp/initial_null_billing
echo "0" > /tmp/initial_wrong_unitprice

# --- INJECT DATA QUALITY ISSUES ---
echo "Injecting data quality issues..."

# Issue 1: Set 15 Invoice records to have NULL BillingAddress
# These are specific InvoiceIds 1-15 (all exist in the 412-invoice Chinook dataset)
mysql -u root -p'GymAnything#2024' chinook -e "
    UPDATE Invoice SET BillingAddress = NULL WHERE InvoiceId IN (1,2,3,4,5,6,7,8,9,10,11,12,13,14,15);
" 2>/dev/null

NULL_COUNT=$(mysql -u root -p'GymAnything#2024' chinook -N -e "
    SELECT COUNT(*) FROM Invoice WHERE BillingAddress IS NULL;
" 2>/dev/null)
echo "Invoices with NULL BillingAddress: ${NULL_COUNT:-0}"
echo "${NULL_COUNT:-0}" > /tmp/initial_null_billing

# Issue 2: Set 3 InvoiceLine UnitPrice values to incorrect 99.99
# These are specific InvoiceLineIds that exist in every Chinook load
mysql -u root -p'GymAnything#2024' chinook -e "
    UPDATE InvoiceLine SET UnitPrice = 99.99 WHERE InvoiceLineId IN (1, 50, 100);
" 2>/dev/null

WRONG_COUNT=$(mysql -u root -p'GymAnything#2024' chinook -N -e "
    SELECT COUNT(*) FROM InvoiceLine il
    JOIN Track t ON il.TrackId = t.TrackId
    WHERE ABS(il.UnitPrice - t.UnitPrice) > 0.001;
" 2>/dev/null)
echo "InvoiceLines with wrong UnitPrice: ${WRONG_COUNT:-0}"
echo "${WRONG_COUNT:-0}" > /tmp/initial_wrong_unitprice

# Clean previous export
rm -f /home/ga/Documents/exports/chinook_genre_sales.csv 2>/dev/null || true

if [ "$(is_workbench_running)" = "false" ]; then
    start_workbench
    sleep 10
fi
focus_workbench

take_screenshot /tmp/task_start_screenshot.png
echo "=== Setup Complete ==="
echo "Chinook database loaded with ${NULL_COUNT:-0} NULL BillingAddress and ${WRONG_COUNT:-0} wrong UnitPrice records."
