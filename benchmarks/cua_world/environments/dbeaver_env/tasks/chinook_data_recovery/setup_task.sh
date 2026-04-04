#!/bin/bash
# Setup script for chinook_data_recovery task
# Prepares production DB (deleted 2009, added 2025) and backup DB (intact 2009)

set -e
echo "=== Setting up Chinook Data Recovery Task ==="

source /workspace/scripts/task_utils.sh

# Paths
DB_DIR="/home/ga/Documents/databases"
PROD_DB="$DB_DIR/chinook.db"
BACKUP_DB="$DB_DIR/chinook_backup.db"
SCRIPTS_DIR="/home/ga/Documents/scripts"

# Ensure directories exist
mkdir -p "$DB_DIR" "$SCRIPTS_DIR"
chown -R ga:ga /home/ga/Documents/

# Ensure base Chinook DB exists (using the environment's default setup logic if needed)
if [ ! -f "$PROD_DB" ]; then
    echo "Downloading Chinook database..."
    wget -q -O "$PROD_DB" "https://github.com/lerocha/chinook-database/raw/master/ChinookDatabase/DataSources/Chinook_Sqlite.sqlite"
fi

# 1. Create the Backup Database (The "Good" State for 2009)
echo "Creating backup database..."
cp "$PROD_DB" "$BACKUP_DB"

# 2. Modify Production Database (The "Bad" State)
echo "Corrupting production database (deleting 2009 data)..."

# Enable Foreign Keys to ensure cascade delete works if configured, otherwise delete manually
# In standard Chinook SQLite, FKs might not be strictly enforced by default depending on driver config,
# so we explicitly delete items then invoices to be safe.
sqlite3 "$PROD_DB" "DELETE FROM invoice_items WHERE InvoiceId IN (SELECT InvoiceId FROM invoices WHERE InvoiceDate LIKE '2009%');"
sqlite3 "$PROD_DB" "DELETE FROM invoices WHERE InvoiceDate LIKE '2009%';"

# 3. Add "New" 2025 Data to Production (The data that MUST be preserved)
# This prevents the agent from just copying the backup file over the production file.
echo "Adding new 2025 data to production..."
sqlite3 "$PROD_DB" <<EOF
INSERT INTO invoices (InvoiceId, CustomerId, InvoiceDate, BillingAddress, BillingCity, BillingCountry, BillingPostalCode, Total)
VALUES 
(1001, 1, '2025-01-01 00:00:00', '123 Recovery Rd', 'Tech City', 'USA', '90210', 10.00),
(1002, 2, '2025-01-02 00:00:00', '456 Backup Blvd', 'Tech City', 'USA', '90210', 5.00),
(1003, 3, '2025-01-03 00:00:00', '789 Restore Ln', 'Tech City', 'USA', '90210', 8.00),
(1004, 4, '2025-01-04 00:00:00', '321 Integrity St', 'Tech City', 'USA', '90210', 15.00),
(1005, 5, '2025-01-05 00:00:00', '654 Snapshot Ave', 'Tech City', 'USA', '90210', 20.00);

INSERT INTO invoice_items (InvoiceLineId, InvoiceId, TrackId, UnitPrice, Quantity)
VALUES
(5001, 1001, 1, 0.99, 10),
(5002, 1002, 2, 0.99, 5),
(5003, 1003, 3, 0.99, 8),
(5004, 1004, 4, 0.99, 15),
(5005, 1005, 5, 0.99, 20);
EOF

# Verify Setup
COUNT_2009=$(sqlite3 "$PROD_DB" "SELECT COUNT(*) FROM invoices WHERE InvoiceDate LIKE '2009%';")
COUNT_2025=$(sqlite3 "$PROD_DB" "SELECT COUNT(*) FROM invoices WHERE InvoiceDate LIKE '2025%';")
BACKUP_2009=$(sqlite3 "$BACKUP_DB" "SELECT COUNT(*) FROM invoices WHERE InvoiceDate LIKE '2009%';")

echo "Setup Verification:"
echo "  Prod 2009 Count (Should be 0): $COUNT_2009"
echo "  Prod 2025 Count (Should be 5): $COUNT_2025"
echo "  Backup 2009 Count (Should be >0): $BACKUP_2009"

if [ "$COUNT_2009" -ne 0 ] || [ "$COUNT_2025" -ne 5 ] || [ "$BACKUP_2009" -eq 0 ]; then
    echo "ERROR: Database setup failed."
    exit 1
fi

# Set permissions
chown ga:ga "$PROD_DB" "$BACKUP_DB"

# Record start time and initial connection count
date +%s > /tmp/task_start_time
CONFIG_DIR="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver"
if [ -f "$CONFIG_DIR/data-sources.json" ]; then
    grep -c '"id"' "$CONFIG_DIR/data-sources.json" > /tmp/initial_connection_count || echo "0" > /tmp/initial_connection_count
else
    echo "0" > /tmp/initial_connection_count
fi

# Ensure DBeaver is running
if ! pgrep -f "dbeaver" > /dev/null; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /usr/share/dbeaver-ce/dbeaver > /tmp/dbeaver.log 2>&1 &"
    sleep 10
fi

# Maximize DBeaver
focus_dbeaver
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="