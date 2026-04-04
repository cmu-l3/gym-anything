#!/bin/bash
# Export script for chinook_invoice_archival task

echo "=== Exporting Archival Results ==="

source /workspace/scripts/task_utils.sh

WORKING_DB="/home/ga/Documents/databases/chinook_working.db"
ARCHIVE_DB="/home/ga/Documents/databases/chinook_archive.db"
CSV_FILE="/home/ga/Documents/exports/archival_reconciliation.csv"
RESULT_FILE="/tmp/archival_result.json"

# 1. Take Final Screenshot
take_screenshot /tmp/task_final.png
sleep 1

# 2. Check DBeaver Connections (names must match)
DBEAVER_CONFIG="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver/data-sources.json"
CONN_WORKING="false"
CONN_ARCHIVE="false"

if [ -f "$DBEAVER_CONFIG" ]; then
    CONN_WORKING=$(grep -q "ChinookWorking" "$DBEAVER_CONFIG" && echo "true" || echo "false")
    CONN_ARCHIVE=$(grep -q "ChinookArchive" "$DBEAVER_CONFIG" && echo "true" || echo "false")
fi

# 3. Analyze Archive DB (if exists)
ARCHIVE_EXISTS="false"
ARCHIVE_INV_COUNT=0
ARCHIVE_ITEM_COUNT=0
ARCHIVE_2009_REV=0.0
ARCHIVE_2010_REV=0.0

if [ -f "$ARCHIVE_DB" ]; then
    ARCHIVE_EXISTS="true"
    ARCHIVE_INV_COUNT=$(sqlite3 "$ARCHIVE_DB" "SELECT COUNT(*) FROM invoices;" 2>/dev/null || echo 0)
    ARCHIVE_ITEM_COUNT=$(sqlite3 "$ARCHIVE_DB" "SELECT COUNT(*) FROM invoice_items;" 2>/dev/null || echo 0)
    # Check years
    ARCHIVE_2009_REV=$(sqlite3 "$ARCHIVE_DB" "SELECT IFNULL(SUM(Total),0) FROM invoices WHERE strftime('%Y', InvoiceDate) = '2009';" 2>/dev/null || echo 0)
    ARCHIVE_2010_REV=$(sqlite3 "$ARCHIVE_DB" "SELECT IFNULL(SUM(Total),0) FROM invoices WHERE strftime('%Y', InvoiceDate) = '2010';" 2>/dev/null || echo 0)
fi

# 4. Analyze Working DB
WORKING_INV_COUNT=0
WORKING_ITEM_COUNT=0
WORKING_2009_COUNT=0
WORKING_2010_COUNT=0
SUMMARY_TABLE_EXISTS="false"
SUMMARY_ROWS=0
SUMMARY_2009_REV=0.0
SUMMARY_2010_REV=0.0

if [ -f "$WORKING_DB" ]; then
    WORKING_INV_COUNT=$(sqlite3 "$WORKING_DB" "SELECT COUNT(*) FROM invoices;" 2>/dev/null || echo 0)
    WORKING_ITEM_COUNT=$(sqlite3 "$WORKING_DB" "SELECT COUNT(*) FROM invoice_items;" 2>/dev/null || echo 0)
    
    # Verify cleanup: Should have 0 rows for 2009/2010
    WORKING_2009_COUNT=$(sqlite3 "$WORKING_DB" "SELECT COUNT(*) FROM invoices WHERE strftime('%Y', InvoiceDate) = '2009';" 2>/dev/null || echo 0)
    WORKING_2010_COUNT=$(sqlite3 "$WORKING_DB" "SELECT COUNT(*) FROM invoices WHERE strftime('%Y', InvoiceDate) = '2010';" 2>/dev/null || echo 0)
    
    # Verify Summary Table
    if sqlite3 "$WORKING_DB" "SELECT name FROM sqlite_master WHERE type='table' AND name='archived_yearly_summary';" | grep -q "archived_yearly_summary"; then
        SUMMARY_TABLE_EXISTS="true"
        SUMMARY_ROWS=$(sqlite3 "$WORKING_DB" "SELECT COUNT(*) FROM archived_yearly_summary;" 2>/dev/null || echo 0)
        SUMMARY_2009_REV=$(sqlite3 "$WORKING_DB" "SELECT IFNULL(TotalRevenue,0) FROM archived_yearly_summary WHERE Year=2009;" 2>/dev/null || echo 0)
        SUMMARY_2010_REV=$(sqlite3 "$WORKING_DB" "SELECT IFNULL(TotalRevenue,0) FROM archived_yearly_summary WHERE Year=2010;" 2>/dev/null || echo 0)
    fi
fi

# 5. Analyze CSV Report
CSV_EXISTS="false"
CSV_HAS_ROWS="false"
if [ -f "$CSV_FILE" ]; then
    CSV_EXISTS="true"
    LINE_COUNT=$(wc -l < "$CSV_FILE")
    if [ "$LINE_COUNT" -gt 3 ]; then
        CSV_HAS_ROWS="true"
    fi
fi

# 6. Generate JSON Result
cat > "$RESULT_FILE" << EOF
{
    "timestamp": $(date +%s),
    "dbeaver_conn_working": $CONN_WORKING,
    "dbeaver_conn_archive": $CONN_ARCHIVE,
    "archive_exists": $ARCHIVE_EXISTS,
    "archive_inv_count": $ARCHIVE_INV_COUNT,
    "archive_item_count": $ARCHIVE_ITEM_COUNT,
    "archive_2009_rev": $ARCHIVE_2009_REV,
    "archive_2010_rev": $ARCHIVE_2010_REV,
    "working_inv_count": $WORKING_INV_COUNT,
    "working_item_count": $WORKING_ITEM_COUNT,
    "working_2009_count": $WORKING_2009_COUNT,
    "working_2010_count": $WORKING_2010_COUNT,
    "summary_table_exists": $SUMMARY_TABLE_EXISTS,
    "summary_rows": $SUMMARY_ROWS,
    "summary_2009_rev": $SUMMARY_2009_REV,
    "summary_2010_rev": $SUMMARY_2010_REV,
    "csv_exists": $CSV_EXISTS,
    "csv_has_rows": $CSV_HAS_ROWS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions
chmod 666 "$RESULT_FILE"

echo "Result JSON saved to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export Complete ==="