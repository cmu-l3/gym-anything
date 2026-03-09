#!/bin/bash
# Export results for chinook_regional_promo_rollout
echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

DB_PATH="/home/ga/Documents/databases/chinook.db"
REPORT_PATH="/home/ga/Documents/exports/promo_impact_analysis.csv"
CAMPAIGN_TAG="spring_promo_2025"

# 1. Check if DBeaver connection exists
CONN_EXISTS=$(check_dbeaver_connection "ChinookOps")

# 2. Database Inspection via SQLite3
echo "Inspecting database state..."

# Check schema for new column
HAS_COLUMN="false"
SCHEMA_INFO=$(sqlite3 "$DB_PATH" "PRAGMA table_info(invoices);" 2>/dev/null)
if echo "$SCHEMA_INFO" | grep -q "campaign_tag"; then
    HAS_COLUMN="true"
fi

# Check insert counts
USA_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM invoices WHERE campaign_tag='$CAMPAIGN_TAG' AND BillingCountry='USA';" 2>/dev/null || echo 0)
CANADA_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM invoices WHERE campaign_tag='$CAMPAIGN_TAG' AND BillingCountry='Canada';" 2>/dev/null || echo 0)
FRANCE_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM invoices WHERE campaign_tag='$CAMPAIGN_TAG' AND BillingCountry='France';" 2>/dev/null || echo 0)

# Check totals
USA_TOTAL=$(sqlite3 "$DB_PATH" "SELECT SUM(Total) FROM invoices WHERE campaign_tag='$CAMPAIGN_TAG' AND BillingCountry='USA';" 2>/dev/null || echo 0)
CANADA_TOTAL=$(sqlite3 "$DB_PATH" "SELECT SUM(Total) FROM invoices WHERE campaign_tag='$CAMPAIGN_TAG' AND BillingCountry='Canada';" 2>/dev/null || echo 0)
FRANCE_TOTAL=$(sqlite3 "$DB_PATH" "SELECT SUM(Total) FROM invoices WHERE campaign_tag='$CAMPAIGN_TAG' AND BillingCountry='France';" 2>/dev/null || echo 0)

# Check address integrity (Did they copy from Customers correctly?)
# We count how many mismatches exist for the new records
# Mismatches in Address, City, State, Country, PostalCode
ADDRESS_MISMATCHES=$(sqlite3 "$DB_PATH" "
SELECT COUNT(*) 
FROM invoices i 
JOIN customers c ON i.CustomerId = c.CustomerId 
WHERE i.campaign_tag='$CAMPAIGN_TAG' 
AND (
    COALESCE(i.BillingAddress,'') != COALESCE(c.Address,'') OR
    COALESCE(i.BillingCity,'') != COALESCE(c.City,'') OR
    COALESCE(i.BillingState,'') != COALESCE(c.State,'') OR
    COALESCE(i.BillingCountry,'') != COALESCE(c.Country,'') OR
    COALESCE(i.BillingPostalCode,'') != COALESCE(c.PostalCode,'')
);" 2>/dev/null || echo 0)

# Check default value handling
# Count rows that are NOT the new campaign and have NULL or empty campaign_tag
# Task said "Existing rows should be treated as 'organic'". 
# If they used DEFAULT 'organic', these should be 'organic'. 
# If they just added column, they might be NULL. 
# We'll give points if they are NOT 'spring_promo_2025' (safety) AND ideally 'organic'.
NON_PROMO_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM invoices WHERE campaign_tag IS NOT '$CAMPAIGN_TAG';" 2>/dev/null || echo 0)
ORGANIC_TAG_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM invoices WHERE campaign_tag = 'organic';" 2>/dev/null || echo 0)

# 3. Check Report File
REPORT_EXISTS="false"
REPORT_CONTENT=""
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    # Read first 10 lines for verification
    REPORT_CONTENT=$(head -n 10 "$REPORT_PATH" | base64 -w 0)
fi

# 4. App State
APP_RUNNING=$(is_dbeaver_running)
take_screenshot /tmp/task_final.png

# 5. Build JSON
cat > /tmp/task_result.json <<EOF
{
    "connection_exists": $CONN_EXISTS,
    "has_column": $HAS_COLUMN,
    "usa_count": $USA_COUNT,
    "canada_count": $CANADA_COUNT,
    "france_count": $FRANCE_COUNT,
    "usa_total": $USA_TOTAL,
    "canada_total": $CANADA_TOTAL,
    "france_total": $FRANCE_TOTAL,
    "address_mismatches": $ADDRESS_MISMATCHES,
    "organic_tag_count": $ORGANIC_TAG_COUNT,
    "non_promo_count": $NON_PROMO_COUNT,
    "report_exists": $REPORT_EXISTS,
    "report_content_b64": "$REPORT_CONTENT",
    "app_running": $APP_RUNNING,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Export complete."
cat /tmp/task_result.json