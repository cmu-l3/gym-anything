#!/bin/bash
# Export script for chinook_acquisition_merger task
# Verifies database state and artifacts

echo "=== Exporting Results ==="
source /workspace/scripts/task_utils.sh

CHINOOK_DB="/home/ga/Documents/databases/chinook.db"
CSV_PATH="/home/ga/Documents/exports/new_acquisitions.csv"
SQL_PATH="/home/ga/Documents/scripts/merge_leads.sql"

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Database Verification
echo "Verifying database state..."

# A. Total Count
FINAL_CUST_COUNT=$(sqlite3 "$CHINOOK_DB" "SELECT COUNT(*) FROM customers;" 2>/dev/null || echo 0)
INITIAL_CUST_COUNT=$(cat /tmp/initial_cust_count 2>/dev/null || echo 0)
ADDED_COUNT=$((FINAL_CUST_COUNT - INITIAL_CUST_COUNT))

# B. Deduplication Check
# Check if 'luisg@embraer.com.br' (an existing customer) appears more than once
DUPLICATE_CHECK=$(sqlite3 "$CHINOOK_DB" "SELECT COUNT(*) FROM customers WHERE Email = 'luisg@embraer.com.br';" 2>/dev/null || echo 0)

# C. Transformation Checks (Name Split & Country Map)
# Check 'Gary Moore' -> FirstName='Gary', LastName='Moore', Country='USA' (mapped from 'US')
GARY_CHECK=$(sqlite3 "$CHINOOK_DB" "SELECT FirstName || '|' || LastName || '|' || Country || '|' || SupportRepId FROM customers WHERE Email = 'gary.moore@example.com';" 2>/dev/null || echo "")

# Check 'Jean Luc' -> Country='Canada' (mapped from 'CA')
JEAN_CHECK=$(sqlite3 "$CHINOOK_DB" "SELECT Country FROM customers WHERE Email = 'j.luc@starfleet.org';" 2>/dev/null || echo "")

# Check 'Pablo Escobar' -> Country='Mexico' (mapped from 'MX')
PABLO_CHECK=$(sqlite3 "$CHINOOK_DB" "SELECT Country FROM customers WHERE Email = 'p.escobar@cartel.mx';" 2>/dev/null || echo "")

# D. Default Value Check
# Check if new records have SupportRepId = 3
REP_CHECK_COUNT=$(sqlite3 "$CHINOOK_DB" "SELECT COUNT(*) FROM customers WHERE SupportRepId = 3 AND Email IN ('gary.moore@example.com', 's.connor@skynet.net');" 2>/dev/null || echo 0)

# 3. Artifact Verification

# A. CSV Check
CSV_EXISTS="false"
CSV_ROWS=0
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_ROWS=$(wc -l < "$CSV_PATH")
    # subtract header
    CSV_ROWS=$((CSV_ROWS - 1))
fi

# B. SQL Script Check
SQL_EXISTS="false"
if [ -f "$SQL_PATH" ]; then
    SQL_EXISTS="true"
fi

# 4. JSON Export
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_count": $INITIAL_CUST_COUNT,
    "final_count": $FINAL_CUST_COUNT,
    "added_count": $ADDED_COUNT,
    "duplicate_check_count": $DUPLICATE_CHECK,
    "gary_record": "$GARY_CHECK",
    "jean_country": "$JEAN_CHECK",
    "pablo_country": "$PABLO_CHECK",
    "rep_check_count": $REP_CHECK_COUNT,
    "csv_exists": $CSV_EXISTS,
    "csv_rows": $CSV_ROWS,
    "sql_exists": $SQL_EXISTS,
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="