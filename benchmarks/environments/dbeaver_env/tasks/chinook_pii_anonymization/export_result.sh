#!/bin/bash
# Export script for chinook_pii_anonymization task
# Verifies database state using SQLite queries and checks output files

echo "=== Exporting PII Anonymization Result ==="

source /workspace/scripts/task_utils.sh

# Configuration
TARGET_DB="/home/ga/Documents/databases/chinook_vendor.db"
REPORT_PATH="/home/ga/Documents/exports/anonymization_report.csv"
SCRIPT_PATH="/home/ga/Documents/scripts/anonymize_customers.sql"
DBEAVER_CONFIG="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver/data-sources.json"

# Capture final screenshot
take_screenshot /tmp/task_final.png

# --- 1. DBeaver Connection Check ---
CONN_EXISTS="false"
if [ -f "$DBEAVER_CONFIG" ]; then
    CONN_EXISTS=$(python3 -c "
import json
try:
    with open('$DBEAVER_CONFIG') as f:
        data = json.load(f)
    found = False
    for k, v in data.get('connections', {}).items():
        if v.get('name') == 'ChinookVendor' and 'chinook_vendor.db' in v.get('configuration', {}).get('database', ''):
            found = True
            break
    print('true' if found else 'false')
except:
    print('false')
" 2>/dev/null)
fi

# --- 2. Database State Verification ---
DB_MODIFIED="false"
ROW_COUNT=0
FIRST_NAME_CORRECT="false"
LAST_NAME_CORRECT="false"
COMPANY_CORRECT="false"
ADDRESS_CORRECT="false"
PHONE_CORRECT="false"
FAX_CORRECT="false"
EMAIL_CORRECT="false"
NON_PII_PRESERVED="false"
INTEGRITY_PRESERVED="false"
INITIAL_NOT_NULL_COMPANIES=$(cat /tmp/initial_not_null_companies.txt 2>/dev/null || echo 0)

if [ -f "$TARGET_DB" ]; then
    # Check modification time
    TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo 0)
    DB_MTIME=$(stat -c %Y "$TARGET_DB" 2>/dev/null || echo 0)
    if [ "$DB_MTIME" -gt "$TASK_START" ]; then
        DB_MODIFIED="true"
    fi

    # Row count (should be 59)
    ROW_COUNT=$(sqlite3 "$TARGET_DB" "SELECT COUNT(*) FROM customers;" 2>/dev/null || echo 0)
    
    # 2.1 Check First Name: All should be 'Customer'
    BAD_FIRST_NAMES=$(sqlite3 "$TARGET_DB" "SELECT COUNT(*) FROM customers WHERE FirstName != 'Customer';" 2>/dev/null || echo 999)
    [ "$BAD_FIRST_NAMES" -eq 0 ] && FIRST_NAME_CORRECT="true"

    # 2.2 Check Last Name: Pattern C###
    # SQLite doesn't have regex, check length and prefix 'C'
    # Pattern: 'C' followed by 3 digits. Length should be 4.
    BAD_LAST_NAMES=$(sqlite3 "$TARGET_DB" "SELECT COUNT(*) FROM customers WHERE LastName NOT LIKE 'C___' OR LENGTH(LastName) != 4;" 2>/dev/null || echo 999)
    # Also verify distinctness roughly (simple check: count distinct should match row count)
    DISTINCT_LAST=$(sqlite3 "$TARGET_DB" "SELECT COUNT(DISTINCT LastName) FROM customers;" 2>/dev/null || echo 0)
    [ "$BAD_LAST_NAMES" -eq 0 ] && [ "$DISTINCT_LAST" -eq "$ROW_COUNT" ] && LAST_NAME_CORRECT="true"

    # 2.3 Check Company: REDACTED count should match initial NOT NULL count
    REDACTED_COMPANIES=$(sqlite3 "$TARGET_DB" "SELECT COUNT(*) FROM customers WHERE Company = 'REDACTED';" 2>/dev/null || echo 0)
    # Also check no original company names remain (anything not NULL or REDACTED)
    BAD_COMPANIES=$(sqlite3 "$TARGET_DB" "SELECT COUNT(*) FROM customers WHERE Company IS NOT NULL AND Company != 'REDACTED';" 2>/dev/null || echo 999)
    # Allow some flex: The requirement is REDACTED if present. 
    # Logic: if initial not nulls == redacted count AND bad companies == 0.
    [ "$REDACTED_COMPANIES" -eq "$INITIAL_NOT_NULL_COMPANIES" ] && [ "$BAD_COMPANIES" -eq 0 ] && COMPANY_CORRECT="true"

    # 2.4 Check Address: All 'REDACTED'
    BAD_ADDRESS=$(sqlite3 "$TARGET_DB" "SELECT COUNT(*) FROM customers WHERE Address != 'REDACTED';" 2>/dev/null || echo 999)
    [ "$BAD_ADDRESS" -eq 0 ] && ADDRESS_CORRECT="true"

    # 2.5 Check Phone/Fax: All NULL
    BAD_PHONE=$(sqlite3 "$TARGET_DB" "SELECT COUNT(*) FROM customers WHERE Phone IS NOT NULL;" 2>/dev/null || echo 999)
    BAD_FAX=$(sqlite3 "$TARGET_DB" "SELECT COUNT(*) FROM customers WHERE Fax IS NOT NULL;" 2>/dev/null || echo 999)
    [ "$BAD_PHONE" -eq 0 ] && [ "$BAD_FAX" -eq 0 ] && PHONE_CORRECT="true" && FAX_CORRECT="true"

    # 2.6 Check Email: customer{ID}@example.com
    # Check logical consistency: ID 1 -> customer1@example.com
    BAD_EMAIL=$(sqlite3 "$TARGET_DB" "SELECT COUNT(*) FROM customers WHERE Email != 'customer' || CustomerId || '@example.com';" 2>/dev/null || echo 999)
    [ "$BAD_EMAIL" -eq 0 ] && EMAIL_CORRECT="true"

    # 2.7 Check Non-PII Preserved (City, Country)
    # Compare distinct countries with original (should be same)
    # Original Chinook has ~24 countries
    COUNTRY_COUNT=$(sqlite3 "$TARGET_DB" "SELECT COUNT(DISTINCT Country) FROM customers;" 2>/dev/null || echo 0)
    [ "$COUNTRY_COUNT" -ge 20 ] && NON_PII_PRESERVED="true"

    # 2.8 Check Referential Integrity
    # Invoices pointing to non-existent customers?
    ORPHAN_INVOICES=$(sqlite3 "$TARGET_DB" "SELECT COUNT(*) FROM invoices WHERE CustomerId NOT IN (SELECT CustomerId FROM customers);" 2>/dev/null || echo 0)
    [ "$ORPHAN_INVOICES" -eq 0 ] && INTEGRITY_PRESERVED="true"
fi

# --- 3. File Deliverables Check ---
REPORT_EXISTS="false"
REPORT_ROWS=0
REPORT_VALID="false"
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_ROWS=$(count_csv_lines "$REPORT_PATH")
    # Header check
    HEADER=$(head -1 "$REPORT_PATH" | tr '[:upper:]' '[:lower:]')
    if [[ "$HEADER" == *"field"* && "$HEADER" == *"action"* && "$HEADER" == *"affected"* ]]; then
        REPORT_VALID="true"
    fi
fi

SCRIPT_EXISTS="false"
SCRIPT_CONTENT_VALID="false"
if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_EXISTS="true"
    # Check for UPDATE statements
    if grep -qi "UPDATE" "$SCRIPT_PATH" && grep -qi "customers" "$SCRIPT_PATH"; then
        SCRIPT_CONTENT_VALID="true"
    fi
fi

# --- 4. Export JSON ---
cat > /tmp/task_result.json << EOF
{
    "dbeaver_connection_exists": $CONN_EXISTS,
    "db_modified": $DB_MODIFIED,
    "row_count": $ROW_COUNT,
    "first_name_correct": $FIRST_NAME_CORRECT,
    "last_name_correct": $LAST_NAME_CORRECT,
    "company_correct": $COMPANY_CORRECT,
    "address_correct": $ADDRESS_CORRECT,
    "phone_fax_correct": $PHONE_CORRECT,
    "email_correct": $EMAIL_CORRECT,
    "non_pii_preserved": $NON_PII_PRESERVED,
    "integrity_preserved": $INTEGRITY_PRESERVED,
    "report_exists": $REPORT_EXISTS,
    "report_row_count": $REPORT_ROWS,
    "report_valid": $REPORT_VALID,
    "script_exists": $SCRIPT_EXISTS,
    "script_valid": $SCRIPT_CONTENT_VALID,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Verification export complete."
cat /tmp/task_result.json