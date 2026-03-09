#!/bin/bash
# Export script for chinook_dedup_cleanup
# Checks database state and output files

echo "=== Exporting Chinook Dedup Cleanup Result ==="

source /workspace/scripts/task_utils.sh

DB_PATH="/home/ga/Documents/databases/chinook_dedup.db"
REPORT_PATH="/home/ga/Documents/exports/dedup_report.csv"
SCRIPT_PATH="/home/ga/Documents/scripts/dedup_cleanup.sql"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo 0)

# 1. Take final screenshot
take_screenshot /tmp/task_end_screenshot.png
sleep 1

# 2. Check Database State
if [ -f "$DB_PATH" ]; then
    # Row counts
    CUST_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM customers" 2>/dev/null || echo -1)
    ARTIST_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM artists" 2>/dev/null || echo -1)
    INVOICE_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM invoices" 2>/dev/null || echo -1)
    ALBUM_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM albums" 2>/dev/null || echo -1)

    # Check for duplicates remaining
    DUP_CUST_GROUPS=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM (SELECT FirstName, LastName, Email, COUNT(*) as c FROM customers GROUP BY FirstName, LastName, Email HAVING c > 1);" 2>/dev/null || echo -1)
    DUP_ARTIST_GROUPS=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM (SELECT Name, COUNT(*) as c FROM artists GROUP BY Name HAVING c > 1);" 2>/dev/null || echo -1)

    # Check for orphaned children (Referential Integrity)
    ORPHAN_INVOICES=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM invoices WHERE CustomerId NOT IN (SELECT CustomerId FROM customers)" 2>/dev/null || echo -1)
    ORPHAN_ALBUMS=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM albums WHERE ArtistId NOT IN (SELECT ArtistId FROM artists)" 2>/dev/null || echo -1)
else
    CUST_COUNT=-1
    ARTIST_COUNT=-1
    INVOICE_COUNT=-1
    ALBUM_COUNT=-1
    DUP_CUST_GROUPS=-1
    DUP_ARTIST_GROUPS=-1
    ORPHAN_INVOICES=-1
    ORPHAN_ALBUMS=-1
fi

# 3. Check DBeaver Connection
DBEAVER_CONFIG="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver/data-sources.json"
CONN_EXISTS="false"
if [ -f "$DBEAVER_CONFIG" ]; then
    if grep -q "ChinookDedup" "$DBEAVER_CONFIG"; then
        CONN_EXISTS="true"
    fi
fi

# 4. Check Output Files
REPORT_EXISTS="false"
REPORT_VALID="false"
RECORDS_REMOVED_CUST=0
RECORDS_REMOVED_ART=0

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    # Basic validation: check headers and extract removal counts
    if grep -qi "DuplicateGroupsFound" "$REPORT_PATH" && grep -qi "RecordsRemoved" "$REPORT_PATH"; then
        # Parse logic: Look for lines with 'customers' and 'artists'
        RECORDS_REMOVED_CUST=$(grep -i "customers" "$REPORT_PATH" | awk -F',' '{print $3}' | tr -d ' ' 2>/dev/null || echo 0)
        RECORDS_REMOVED_ART=$(grep -i "artists" "$REPORT_PATH" | awk -F',' '{print $3}' | tr -d ' ' 2>/dev/null || echo 0)
        REPORT_VALID="true"
    fi
fi

SCRIPT_EXISTS="false"
if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_EXISTS="true"
    SCRIPT_SIZE=$(stat -c%s "$SCRIPT_PATH" 2>/dev/null || echo 0)
fi

# 5. Compile Result JSON
cat > /tmp/dedup_result.json << EOF
{
    "db_exists": $([ -f "$DB_PATH" ] && echo "true" || echo "false"),
    "connection_exists": $CONN_EXISTS,
    "final_cust_count": $CUST_COUNT,
    "final_artist_count": $ARTIST_COUNT,
    "final_invoice_count": $INVOICE_COUNT,
    "final_album_count": $ALBUM_COUNT,
    "dup_cust_groups": $DUP_CUST_GROUPS,
    "dup_artist_groups": $DUP_ARTIST_GROUPS,
    "orphan_invoices": $ORPHAN_INVOICES,
    "orphan_albums": $ORPHAN_ALBUMS,
    "report_exists": $REPORT_EXISTS,
    "report_valid": $REPORT_VALID,
    "report_removed_cust": "${RECORDS_REMOVED_CUST:-0}",
    "report_removed_art": "${RECORDS_REMOVED_ART:-0}",
    "script_exists": $SCRIPT_EXISTS,
    "timestamp": $(date +%s)
}
EOF

echo "Result JSON:"
cat /tmp/dedup_result.json
echo "=== Export Complete ==="