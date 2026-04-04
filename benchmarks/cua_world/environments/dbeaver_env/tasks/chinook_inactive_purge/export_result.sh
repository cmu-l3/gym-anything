#!/bin/bash
# Export script for chinook_inactive_purge task
# Verifies the final state of the database and the exported CSV

echo "=== Exporting Chinook Inactive Purge Result ==="

source /workspace/scripts/task_utils.sh

# Config
DB_PATH="/home/ga/Documents/databases/chinook.db"
EXPORT_CSV="/home/ga/Documents/exports/inactive_customers.csv"
SQL_SCRIPT="/home/ga/Documents/scripts/purge_process.sql"
GT_FILE="/tmp/purge_ground_truth.json"

# Capture final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Check if DB exists (sanity check)
if [ ! -f "$DB_PATH" ]; then
    echo "CRITICAL: Database file deleted!"
    DB_EXISTS="false"
else
    DB_EXISTS="true"
fi

# Load Ground Truth
if [ -f "$GT_FILE" ]; then
    EXPECTED_INACTIVE_COUNT=$(python3 -c "import json; print(json.load(open('$GT_FILE'))['expected_inactive_count'])")
    SAMPLE_INACTIVE_ID=$(python3 -c "import json; print(json.load(open('$GT_FILE'))['sample_inactive_id'])")
    SAMPLE_ACTIVE_ID=$(python3 -c "import json; print(json.load(open('$GT_FILE'))['sample_active_id'])")
    ALL_INACTIVE_IDS=$(python3 -c "import json; print(','.join(map(str, json.load(open('$GT_FILE'))['inactive_ids'])))")
else
    echo "CRITICAL: Ground truth file missing."
    EXPECTED_INACTIVE_COUNT=0
    SAMPLE_INACTIVE_ID=0
    SAMPLE_ACTIVE_ID=0
    ALL_INACTIVE_IDS=""
fi

# --- VERIFICATION 1: Database State ---

# Count remaining customers
REMAINING_CUSTOMERS=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM customers;" 2>/dev/null || echo 0)

# Check if the specific inactive sample ID is gone
if [ "$SAMPLE_INACTIVE_ID" != "None" ]; then
    INACTIVE_STILL_EXISTS=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM customers WHERE CustomerId = $SAMPLE_INACTIVE_ID;" 2>/dev/null || echo 0)
else
    INACTIVE_STILL_EXISTS=0
fi

# Check if the specific active sample ID still exists
if [ "$SAMPLE_ACTIVE_ID" != "None" ]; then
    ACTIVE_STILL_EXISTS=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM customers WHERE CustomerId = $SAMPLE_ACTIVE_ID;" 2>/dev/null || echo 0)
else
    ACTIVE_STILL_EXISTS=0
fi

# Check for Orphans (Integrity Check)
# 1. Invoices belonging to deleted customers?
# (We check if there are invoices where CustomerId is NOT in the current customers table)
ORPHAN_INVOICES=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM invoices WHERE CustomerId NOT IN (SELECT CustomerId FROM customers);" 2>/dev/null || echo 0)

# 2. InvoiceItems belonging to deleted invoices?
# (We check if there are items where InvoiceId is NOT in the current invoices table)
ORPHAN_ITEMS=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM invoice_items WHERE InvoiceId NOT IN (SELECT InvoiceId FROM invoices);" 2>/dev/null || echo 0)


# --- VERIFICATION 2: CSV Export ---

CSV_EXISTS="false"
CSV_ROW_COUNT=0
CSV_COLUMNS_VALID="false"
CSV_HEADERS=""

if [ -f "$EXPORT_CSV" ]; then
    CSV_EXISTS="true"
    # Count rows (minus header)
    CSV_ROW_COUNT=$(count_csv_lines "$EXPORT_CSV")
    
    # Check headers
    CSV_HEADERS=$(head -1 "$EXPORT_CSV" | tr -d '\r')
    
    # Verify required columns exist (case-insensitive check handled in verifier.py logic usually, but strict here)
    if echo "$CSV_HEADERS" | grep -qi "CustomerId" && \
       echo "$CSV_HEADERS" | grep -qi "TotalSpent"; then
        CSV_COLUMNS_VALID="true"
    fi
fi

# --- VERIFICATION 3: SQL Script ---
SCRIPT_EXISTS="false"
if [ -f "$SQL_SCRIPT" ]; then
    SCRIPT_EXISTS="true"
fi

# --- VERIFICATION 4: Connection Check ---
# Check if DBeaver has a connection named "Chinook"
CONN_EXISTS=$(check_dbeaver_connection "Chinook")

# Prepare Result JSON
cat > /tmp/purge_result.json << EOF
{
    "db_exists": $DB_EXISTS,
    "remaining_customers": $REMAINING_CUSTOMERS,
    "sample_inactive_still_exists": $INACTIVE_STILL_EXISTS,
    "sample_active_still_exists": $ACTIVE_STILL_EXISTS,
    "orphan_invoices": $ORPHAN_INVOICES,
    "orphan_items": $ORPHAN_ITEMS,
    "csv_exists": $CSV_EXISTS,
    "csv_row_count": $CSV_ROW_COUNT,
    "csv_columns_valid": $CSV_COLUMNS_VALID,
    "csv_headers": "$CSV_HEADERS",
    "script_exists": $SCRIPT_EXISTS,
    "connection_exists": $CONN_EXISTS,
    "expected_inactive_count": $EXPECTED_INACTIVE_COUNT,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Result JSON generated:"
cat /tmp/purge_result.json

echo "=== Export Complete ==="