#!/bin/bash
# Export script for chinook_data_recovery task
# Checks the state of the production database after recovery

echo "=== Exporting Chinook Data Recovery Results ==="

source /workspace/scripts/task_utils.sh

PROD_DB="/home/ga/Documents/databases/chinook.db"
SCRIPT_PATH="/home/ga/Documents/scripts/recovery_script.sql"

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Verify 2025 Data (Anti-Gaming Check)
# If the agent just overwrote the file with the backup, this count will be 0.
COUNT_2025_INVOICES=$(sqlite3 "$PROD_DB" "SELECT COUNT(*) FROM invoices WHERE InvoiceDate LIKE '2025%';" 2>/dev/null || echo 0)
COUNT_2025_ITEMS=$(sqlite3 "$PROD_DB" "SELECT COUNT(*) FROM invoice_items WHERE InvoiceId IN (SELECT InvoiceId FROM invoices WHERE InvoiceDate LIKE '2025%');" 2>/dev/null || echo 0)

# 2. Verify 2009 Data Restoration (Success Criteria)
COUNT_2009_INVOICES=$(sqlite3 "$PROD_DB" "SELECT COUNT(*) FROM invoices WHERE InvoiceDate LIKE '2009%';" 2>/dev/null || echo 0)
COUNT_2009_ITEMS=$(sqlite3 "$PROD_DB" "SELECT COUNT(*) FROM invoice_items WHERE InvoiceId IN (SELECT InvoiceId FROM invoices WHERE InvoiceDate LIKE '2009%');" 2>/dev/null || echo 0)

# 3. Verify Data Integrity (Revenue Check)
# Sum of Total for 2009 invoices. Ground truth is approx 449.46
REVENUE_2009=$(sqlite3 "$PROD_DB" "SELECT SUM(Total) FROM invoices WHERE InvoiceDate LIKE '2009%';" 2>/dev/null || echo 0)

# 4. Check for Script
SCRIPT_EXISTS="false"
if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_EXISTS="true"
fi

# 5. Check DBeaver Connection Count (Did they connect to both?)
CONFIG_DIR="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver"
FINAL_CONN_COUNT=0
if [ -f "$CONFIG_DIR/data-sources.json" ]; then
    FINAL_CONN_COUNT=$(grep -c '"id"' "$CONFIG_DIR/data-sources.json" || echo 0)
fi
INITIAL_CONN_COUNT=$(cat /tmp/initial_connection_count 2>/dev/null || echo 0)

# Export JSON
cat > /tmp/recovery_result.json <<EOF
{
    "count_2025_invoices": $COUNT_2025_INVOICES,
    "count_2025_items": $COUNT_2025_ITEMS,
    "count_2009_invoices": $COUNT_2009_INVOICES,
    "count_2009_items": $COUNT_2009_ITEMS,
    "revenue_2009": "$REVENUE_2009",
    "script_exists": $SCRIPT_EXISTS,
    "initial_conn_count": $INITIAL_CONN_COUNT,
    "final_conn_count": $FINAL_CONN_COUNT,
    "timestamp": "$(date +%s)"
}
EOF

# Move to safe location
cp /tmp/recovery_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Results exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="