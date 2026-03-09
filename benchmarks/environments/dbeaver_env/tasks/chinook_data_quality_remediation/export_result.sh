#!/bin/bash
# Export script for chinook_data_quality_remediation task

echo "=== Exporting Chinook Data Quality Remediation Result ==="

source /workspace/scripts/task_utils.sh

AUDIT_DB="/home/ga/Documents/databases/chinook_audit.db"
AUDIT_CSV="/home/ga/Documents/exports/quality_audit.csv"
DBEAVER_CONFIG="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver/data-sources.json"

take_screenshot /tmp/chinook_quality_task_end.png
sleep 1

# Check DBeaver connection for ChinookAudit
CHINOOK_AUDIT_CONN="false"
if [ -f "$DBEAVER_CONFIG" ]; then
    CHINOOK_AUDIT_CONN=$(python3 -c "
import json, sys
try:
    with open('$DBEAVER_CONFIG') as f:
        config = json.load(f)
    for k, v in config.get('connections', {}).items():
        if v.get('name', '').lower() == 'chinookaudit':
            print('true')
            sys.exit(0)
    print('false')
except:
    print('false')
" 2>/dev/null || echo false)
fi

# Check database fixes
REMAINING_ORPHANS=0
REMAINING_NULL_COMPOSERS=0
AUDIT_DB_EXISTS="false"

if [ -f "$AUDIT_DB" ]; then
    AUDIT_DB_EXISTS="true"

    # Orphaned invoice_items (should be 0 if fixed)
    REMAINING_ORPHANS=$(sqlite3 "$AUDIT_DB" \
        "SELECT COUNT(*) FROM invoice_items WHERE InvoiceId NOT IN (SELECT InvoiceId FROM invoices)" \
        2>/dev/null || echo -1)

    # NULL Rock composers (should be 0 if fixed)
    ROCK_GENRE_ID=$(sqlite3 "$AUDIT_DB" "SELECT GenreId FROM genres WHERE Name='Rock' LIMIT 1" 2>/dev/null || echo 1)
    REMAINING_NULL_COMPOSERS=$(sqlite3 "$AUDIT_DB" \
        "SELECT COUNT(*) FROM tracks WHERE GenreId=$ROCK_GENRE_ID AND (Composer IS NULL OR Composer='')" \
        2>/dev/null || echo -1)

    # Check that 'Unknown' was used for fixes
    UNKNOWN_COMPOSER_COUNT=$(sqlite3 "$AUDIT_DB" \
        "SELECT COUNT(*) FROM tracks WHERE GenreId=$ROCK_GENRE_ID AND Composer='Unknown'" \
        2>/dev/null || echo 0)
fi

# Check audit CSV
CSV_EXISTS="false"
CSV_ROW_COUNT=0
CSV_HAS_ORPHAN_ROW="false"
CSV_HAS_COMPOSER_ROW="false"
CSV_HAS_EMAIL_ROW="false"
CSV_ORPHAN_COUNT=0
CSV_COMPOSER_COUNT=0
CSV_EMAIL_COUNT=0

if [ -f "$AUDIT_CSV" ]; then
    CSV_EXISTS="true"
    CSV_ROW_COUNT=$(count_csv_lines "$AUDIT_CSV")

    # Check for required issue type rows
    CSV_CONTENT=$(cat "$AUDIT_CSV" | tr '[:upper:]' '[:lower:]')
    echo "$CSV_CONTENT" | grep -qi "orphan" && CSV_HAS_ORPHAN_ROW="true"
    echo "$CSV_CONTENT" | grep -qi "composer\|null_rock\|rock" && CSV_HAS_COMPOSER_ROW="true"
    echo "$CSV_CONTENT" | grep -qi "email\|invalid" && CSV_HAS_EMAIL_ROW="true"

    # Extract record counts from CSV
    CSV_ORPHAN_COUNT=$(python3 -c "
import csv, sys
try:
    with open('$AUDIT_CSV') as f:
        reader = csv.DictReader(f)
        headers = [h.lower().strip() for h in (reader.fieldnames or [])]
        # Find RecordsAffected column
        rec_col = next((h for h in reader.fieldnames or [] if 'record' in h.lower() or 'count' in h.lower() or 'affected' in h.lower()), None)
        for row in reader:
            issue = str(row.get('IssueType', row.get('issuetype', ''))).lower()
            if 'orphan' in issue and rec_col:
                val = row.get(rec_col, '0').strip()
                try:
                    print(int(float(val)))
                    sys.exit(0)
                except:
                    pass
    print(0)
except:
    print(0)
" 2>/dev/null || echo 0)
fi

# Read ground truth
GT_ORPHANS=$(cat /tmp/initial_orphaned_count 2>/dev/null || echo 0)
GT_NULL_COMPOSERS=$(cat /tmp/initial_null_composers 2>/dev/null || echo 0)
GT_INVALID_EMAILS=$(cat /tmp/initial_invalid_emails 2>/dev/null || echo 0)

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo 0)
CSV_CREATED_AFTER_START="false"
if [ -f "$AUDIT_CSV" ]; then
    FILE_TIME=$(stat -c%Y "$AUDIT_CSV" 2>/dev/null || stat -f%m "$AUDIT_CSV" 2>/dev/null || echo 0)
    [ "$FILE_TIME" -gt "$TASK_START" ] && CSV_CREATED_AFTER_START="true"
fi

cat > /tmp/chinook_quality_result.json << EOF
{
    "chinook_audit_conn_found": $CHINOOK_AUDIT_CONN,
    "audit_db_exists": $AUDIT_DB_EXISTS,
    "remaining_orphaned_items": $REMAINING_ORPHANS,
    "remaining_null_rock_composers": $REMAINING_NULL_COMPOSERS,
    "unknown_composer_count": ${UNKNOWN_COMPOSER_COUNT:-0},
    "csv_exists": $CSV_EXISTS,
    "csv_row_count": $CSV_ROW_COUNT,
    "csv_has_orphan_row": $CSV_HAS_ORPHAN_ROW,
    "csv_has_composer_row": $CSV_HAS_COMPOSER_ROW,
    "csv_has_email_row": $CSV_HAS_EMAIL_ROW,
    "csv_orphan_count_reported": $CSV_ORPHAN_COUNT,
    "csv_created_after_start": $CSV_CREATED_AFTER_START,
    "gt_orphaned_items": $GT_ORPHANS,
    "gt_null_composers": $GT_NULL_COMPOSERS,
    "gt_invalid_emails": $GT_INVALID_EMAILS,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result:"
cat /tmp/chinook_quality_result.json
echo ""
echo "=== Export Complete ==="
