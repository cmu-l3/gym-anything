#!/bin/bash
# Setup script for chinook_invoice_archival task

echo "=== Setting up Chinook Invoice Archival Task ==="

source /workspace/scripts/task_utils.sh

# Paths
SOURCE_DB="/home/ga/Documents/databases/chinook.db"
WORKING_DB="/home/ga/Documents/databases/chinook_working.db"
ARCHIVE_DB="/home/ga/Documents/databases/chinook_archive.db"
EXPORT_DIR="/home/ga/Documents/exports"
GROUND_TRUTH_FILE="/tmp/ground_truth.json"

# Ensure clean slate
rm -f "$WORKING_DB" "$ARCHIVE_DB"
rm -f "$EXPORT_DIR/archival_reconciliation.csv"
mkdir -p "$EXPORT_DIR"

# Verify source DB exists
if [ ! -f "$SOURCE_DB" ]; then
    echo "ERROR: Source Chinook database not found at $SOURCE_DB"
    exit 1
fi

# Create working copy
cp "$SOURCE_DB" "$WORKING_DB"
chown ga:ga "$WORKING_DB"
echo "Created working database: $WORKING_DB"

# --- Compute Ground Truth (using python/sqlite3) ---
# We calculate the expected values for 2009/2010 before the agent starts.
# This ensures we have a rigid baseline for verification.
echo "Computing ground truth values..."

python3 << PYEOF
import sqlite3
import json

db_path = "$WORKING_DB"
conn = sqlite3.connect(db_path)
c = conn.cursor()

def get_stats(year):
    # Invoice count
    c.execute(f"SELECT COUNT(*) FROM invoices WHERE strftime('%Y', InvoiceDate) = '{year}'")
    inv_count = c.fetchone()[0]
    
    # Invoice Items count
    c.execute(f"SELECT COUNT(*) FROM invoice_items ii JOIN invoices i ON ii.InvoiceId = i.InvoiceId WHERE strftime('%Y', i.InvoiceDate) = '{year}'")
    item_count = c.fetchone()[0]
    
    # Revenue
    c.execute(f"SELECT SUM(Total) FROM invoices WHERE strftime('%Y', InvoiceDate) = '{year}'")
    revenue = c.fetchone()[0] or 0.0
    
    # Unique Customers
    c.execute(f"SELECT COUNT(DISTINCT CustomerId) FROM invoices WHERE strftime('%Y', InvoiceDate) = '{year}'")
    cust_count = c.fetchone()[0]
    
    # Avg Total
    avg_total = revenue / inv_count if inv_count > 0 else 0.0
    
    return {
        "count": inv_count,
        "items": item_count,
        "revenue": revenue,
        "customers": cust_count,
        "avg": avg_total
    }

# Global totals
c.execute("SELECT COUNT(*) FROM invoices")
total_inv = c.fetchone()[0]
c.execute("SELECT COUNT(*) FROM invoice_items")
total_items = c.fetchone()[0]

stats_2009 = get_stats('2009')
stats_2010 = get_stats('2010')

# Expected remaining (post-archive)
expected_remaining_inv = total_inv - stats_2009['count'] - stats_2010['count']
expected_remaining_items = total_items - stats_2009['items'] - stats_2010['items']

gt = {
    "original": {
        "invoices": total_inv,
        "items": total_items
    },
    "archive": {
        "2009": stats_2009,
        "2010": stats_2010,
        "total_invoices": stats_2009['count'] + stats_2010['count'],
        "total_items": stats_2009['items'] + stats_2010['items']
    },
    "working_remaining": {
        "invoices": expected_remaining_inv,
        "items": expected_remaining_items
    }
}

with open('$GROUND_TRUTH_FILE', 'w') as f:
    json.dump(gt, f, indent=2)

print("Ground truth computed.")
PYEOF

# Ensure DBeaver is running
if ! is_dbeaver_running; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 dbeaver &" > /dev/null 2>&1 &
    sleep 10
fi

# Focus DBeaver
focus_dbeaver || true

# Record start time
date +%s > /tmp/task_start_timestamp

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="