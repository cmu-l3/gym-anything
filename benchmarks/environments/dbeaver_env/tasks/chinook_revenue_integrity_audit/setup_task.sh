#!/bin/bash
# Setup script for chinook_revenue_integrity_audit
# Creates a corrupted version of the Chinook database for the agent to audit

set -e
echo "=== Setting up Chinook Revenue Integrity Audit ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Define paths
SOURCE_DB="/home/ga/Documents/databases/chinook.db"
AUDIT_DB="/home/ga/Documents/databases/chinook_audit.db"
EXPORT_DIR="/home/ga/Documents/exports"
SCRIPTS_DIR="/home/ga/Documents/scripts"

# Create directories
mkdir -p "$EXPORT_DIR" "$SCRIPTS_DIR"
chown -R ga:ga /home/ga/Documents/

# Remove artifacts from previous runs
rm -f "$EXPORT_DIR/invoice_discrepancies.csv"
rm -f "$SCRIPTS_DIR/audit_query.sql"

# Verify source database exists
if [ ! -f "$SOURCE_DB" ]; then
    echo "ERROR: Source Chinook database not found at $SOURCE_DB"
    # Fallback: try to download or setup if missing (using the environment's setup script logic)
    /workspace/scripts/setup_dbeaver.sh
fi

# Create the audit database copy
echo "Creating audit database..."
cp "$SOURCE_DB" "$AUDIT_DB"
chmod 644 "$AUDIT_DB"
chown ga:ga "$AUDIT_DB"

# Inject Data Corruptions using Python
# We modify specific invoices so their 'Total' does not match sum(items)
echo "Injecting financial discrepancies..."
python3 -c "
import sqlite3

db_path = '$AUDIT_DB'
conn = sqlite3.connect(db_path)
c = conn.cursor()

# Format: (InvoiceId, OffsetAmount)
# OffsetAmount = Value added to the correct total to make it wrong
anomalies = [
    (10, 5.00),     # Stored is 5.00 higher than actual
    (55, -2.00),    # Stored is 2.00 lower than actual
    (120, 10.50),   # Stored is 10.50 higher
    (250, 0.99),    # Small error
    (310, -100.00)  # Large under-reporting
]

print(f'Injecting {len(anomalies)} anomalies...')

for inv_id, offset in anomalies:
    # 1. Get current valid total (assuming source DB is correct)
    c.execute('SELECT Total FROM invoices WHERE InvoiceId = ?', (inv_id,))
    row = c.fetchone()
    if row:
        current_total = row[0]
        new_fake_total = round(current_total + offset, 2)
        
        # 2. Update the invoice record with the WRONG total
        c.execute('UPDATE invoices SET Total = ? WHERE InvoiceId = ?', (new_fake_total, inv_id))
        print(f'  Corrupted Invoice {inv_id}: Real={current_total} -> Fake={new_fake_total} (Offset={offset})')

conn.commit()
conn.close()
"

# Start DBeaver if not running
if ! is_dbeaver_running; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /usr/share/dbeaver-ce/dbeaver > /tmp/dbeaver.log 2>&1 &"
    sleep 10
fi

# Focus DBeaver and maximize
focus_dbeaver
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="