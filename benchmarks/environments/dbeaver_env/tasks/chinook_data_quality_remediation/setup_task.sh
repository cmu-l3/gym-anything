#!/bin/bash
# Setup script for chinook_data_quality_remediation task
# Creates a copy of the Chinook DB with introduced data quality issues

set -e
echo "=== Setting up Chinook Data Quality Remediation Task ==="

source /workspace/scripts/task_utils.sh

CHINOOK_DB="/home/ga/Documents/databases/chinook.db"
AUDIT_DB="/home/ga/Documents/databases/chinook_audit.db"
EXPORT_DIR="/home/ga/Documents/exports"

mkdir -p "$EXPORT_DIR" /home/ga/Documents/databases
chown -R ga:ga /home/ga/Documents/

# Remove any pre-existing audit output
rm -f "$EXPORT_DIR/quality_audit.csv"

# Verify source Chinook database exists
if [ ! -f "$CHINOOK_DB" ]; then
    echo "ERROR: Source Chinook database not found at $CHINOOK_DB"
    exit 1
fi

# Create fresh copy of Chinook as the audit database
echo "Creating audit database copy..."
cp "$CHINOOK_DB" "$AUDIT_DB"
chown ga:ga "$AUDIT_DB"

# Verify the copy worked
TABLE_COUNT=$(sqlite3 "$AUDIT_DB" "SELECT COUNT(*) FROM sqlite_master WHERE type='table'" 2>/dev/null || echo 0)
if [ "$TABLE_COUNT" -lt 5 ]; then
    echo "ERROR: Audit database copy appears incomplete ($TABLE_COUNT tables)"
    exit 1
fi

echo "Introducing data quality issues into audit database..."

# --- Issue 1: Create orphaned invoice_items by deleting parent invoices ---
# Delete invoices 1-6 (we know these exist in Chinook). This leaves their
# invoice_items as orphaned records referencing non-existent invoices.
ORPHAN_COUNT=$(sqlite3 "$AUDIT_DB" "SELECT COUNT(*) FROM invoice_items WHERE InvoiceId IN (1,2,3,4,5,6)" 2>/dev/null || echo 0)
echo "Orphaned invoice_items that will be created: $ORPHAN_COUNT"

sqlite3 "$AUDIT_DB" "DELETE FROM invoices WHERE InvoiceId IN (1,2,3,4,5,6);"
VERIFY_ORPHANS=$(sqlite3 "$AUDIT_DB" "SELECT COUNT(*) FROM invoice_items WHERE InvoiceId NOT IN (SELECT InvoiceId FROM invoices)" 2>/dev/null || echo 0)
echo "Verified orphaned invoice_items count: $VERIFY_ORPHANS"

# --- Issue 2: Null out Composer for Rock tracks in range 1-200 ---
# Get the Rock genre ID
ROCK_GENRE_ID=$(sqlite3 "$AUDIT_DB" "SELECT GenreId FROM genres WHERE Name='Rock' LIMIT 1" 2>/dev/null || echo 1)
echo "Rock GenreId: $ROCK_GENRE_ID"

# Count how many tracks we will nullify
NULL_COMPOSER_COUNT=$(sqlite3 "$AUDIT_DB" "SELECT COUNT(*) FROM tracks WHERE TrackId BETWEEN 1 AND 200 AND GenreId=$ROCK_GENRE_ID AND Composer IS NOT NULL" 2>/dev/null || echo 0)
echo "Rock tracks with Composer that will be nullified: $NULL_COMPOSER_COUNT"

sqlite3 "$AUDIT_DB" "UPDATE tracks SET Composer = NULL WHERE TrackId BETWEEN 1 AND 200 AND GenreId=$ROCK_GENRE_ID;"

VERIFY_NULL_COMPOSERS=$(sqlite3 "$AUDIT_DB" "SELECT COUNT(*) FROM tracks WHERE GenreId=$ROCK_GENRE_ID AND Composer IS NULL" 2>/dev/null || echo 0)
echo "Verified NULL Rock composer count: $VERIFY_NULL_COMPOSERS"

# --- Issue 3: Identify existing invalid emails (don't modify, just count for GT) ---
INVALID_EMAIL_COUNT=$(sqlite3 "$AUDIT_DB" "SELECT COUNT(*) FROM customers WHERE Email NOT LIKE '%@%.%'" 2>/dev/null || echo 0)
echo "Customers with invalid email format: $INVALID_EMAIL_COUNT"

# Save ground truth to /tmp
python3 << PYEOF
import json

ground_truth = {
    "orphaned_invoice_items": $VERIFY_ORPHANS,
    "null_rock_composers": $VERIFY_NULL_COMPOSERS,
    "invalid_emails": $INVALID_EMAIL_COUNT,
    "rock_genre_id": $ROCK_GENRE_ID,
    "original_null_composer_count": $NULL_COMPOSER_COUNT,
    "deleted_invoices": [1, 2, 3, 4, 5, 6]
}

with open('/tmp/chinook_quality_gt.json', 'w') as f:
    json.dump(ground_truth, f, indent=2)

print(f"Ground truth saved:")
print(f"  Orphaned invoice_items: {ground_truth['orphaned_invoice_items']}")
print(f"  NULL Rock composers: {ground_truth['null_rock_composers']}")
print(f"  Invalid emails: {ground_truth['invalid_emails']}")
PYEOF

# Record baseline state for anti-gaming
echo "$VERIFY_ORPHANS" > /tmp/initial_orphaned_count
echo "$VERIFY_NULL_COMPOSERS" > /tmp/initial_null_composers
echo "$INVALID_EMAIL_COUNT" > /tmp/initial_invalid_emails

# Record initial DBeaver connection count
DBEAVER_CONFIG="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver/data-sources.json"
INITIAL_CONN_COUNT=0
if [ -f "$DBEAVER_CONFIG" ]; then
    INITIAL_CONN_COUNT=$(python3 -c "
import json
try:
    with open('$DBEAVER_CONFIG') as f:
        config = json.load(f)
    print(len(config.get('connections', {})))
except:
    print(0)
" 2>/dev/null || echo 0)
fi
echo "$INITIAL_CONN_COUNT" > /tmp/initial_dbeaver_conn_count

# Record task start timestamp
date +%s > /tmp/task_start_timestamp
echo "Task started at: $(date)"

# Ensure DBeaver is running
if ! is_dbeaver_running; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 dbeaver &" 2>/dev/null &
    sleep 8
fi
focus_dbeaver || true
sleep 2

# Take initial screenshot
take_screenshot /tmp/chinook_quality_task_start.png
echo "=== Chinook Data Quality Setup Complete ==="
