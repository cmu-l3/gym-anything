#!/bin/bash
echo "=== Exporting import_database_dump results ==="

source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_TABLE_COUNT=$(cat /tmp/initial_table_count.txt 2>/dev/null || echo "0")

# 1. Check Database State
DB_NAME="acmecorp_chinook"
DB_EXISTS="false"
TABLE_COUNT=0
ARTIST_COUNT=0
TRACK_COUNT=0
CUSTOMER_COUNT=0
INVOICE_COUNT=0
CHECK_VALUE=""
TABLES_MODIFIED_RECENTLY="false"

# Check if DB exists
if mysql_database_exists "$DB_NAME"; then
    DB_EXISTS="true"
    
    # Count tables
    TABLE_COUNT=$(mysql -u root -pGymAnything123! -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DB_NAME}';" 2>/dev/null || echo "0")
    
    # Count rows in key tables (if they exist)
    ARTIST_COUNT=$(mysql -u root -pGymAnything123! -N -e "SELECT COUNT(*) FROM ${DB_NAME}.Artist;" 2>/dev/null || echo "0")
    TRACK_COUNT=$(mysql -u root -pGymAnything123! -N -e "SELECT COUNT(*) FROM ${DB_NAME}.Track;" 2>/dev/null || echo "0")
    CUSTOMER_COUNT=$(mysql -u root -pGymAnything123! -N -e "SELECT COUNT(*) FROM ${DB_NAME}.Customer;" 2>/dev/null || echo "0")
    INVOICE_COUNT=$(mysql -u root -pGymAnything123! -N -e "SELECT COUNT(*) FROM ${DB_NAME}.Invoice;" 2>/dev/null || echo "0")
    
    # Check specific value (ArtistId 1 should be AC/DC)
    CHECK_VALUE=$(mysql -u root -pGymAnything123! -N -e "SELECT Name FROM ${DB_NAME}.Artist WHERE ArtistId=1 LIMIT 1;" 2>/dev/null || echo "")

    # Anti-gaming: Check if any tables were created/modified after task start
    # We check information_schema.tables CREATE_TIME or UPDATE_TIME
    RECENT_TABLES=$(mysql -u root -pGymAnything123! -N -e "
        SELECT COUNT(*) FROM information_schema.tables 
        WHERE table_schema='${DB_NAME}' 
        AND (create_time >= FROM_UNIXTIME(${TASK_START}) OR update_time >= FROM_UNIXTIME(${TASK_START}));" 2>/dev/null || echo "0")
        
    if [ "$RECENT_TABLES" -gt 0 ]; then
        TABLES_MODIFIED_RECENTLY="true"
    fi
fi

# 2. Check Firefox State
FIREFOX_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# 3. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 4. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_table_count": $INITIAL_TABLE_COUNT,
    "db_exists": $DB_EXISTS,
    "final_table_count": $TABLE_COUNT,
    "row_counts": {
        "Artist": $ARTIST_COUNT,
        "Track": $TRACK_COUNT,
        "Customer": $CUSTOMER_COUNT,
        "Invoice": $INVOICE_COUNT
    },
    "check_value": "$(json_escape "$CHECK_VALUE")",
    "tables_modified_during_task": $TABLES_MODIFIED_RECENTLY,
    "firefox_running": $FIREFOX_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="