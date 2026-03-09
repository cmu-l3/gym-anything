#!/bin/bash
# Export script for airport_schema_normalization task

echo "=== Exporting Airport Schema Normalization Result ==="

source /workspace/scripts/task_utils.sh

AIRPORTS_DB="/home/ga/Documents/databases/airports_flat.db"
REPORT_FILE="/home/ga/Documents/exports/normalization_report.txt"
DBEAVER_CONFIG="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver/data-sources.json"

take_screenshot /tmp/airports_task_end.png
sleep 1

# Check DBeaver 'Airports' connection
AIRPORTS_CONN_FOUND="false"
if [ -f "$DBEAVER_CONFIG" ]; then
    AIRPORTS_CONN_FOUND=$(python3 -c "
import json, sys
try:
    with open('$DBEAVER_CONFIG') as f:
        config = json.load(f)
    for k, v in config.get('connections', {}).items():
        if v.get('name', '').lower() == 'airports':
            print('true')
            sys.exit(0)
    print('false')
except:
    print('false')
" 2>/dev/null || echo false)
fi

# Check database state
AIRPORTS_DB_EXISTS="false"
COUNTRIES_TABLE_EXISTS="false"
TIMEZONES_TABLE_EXISTS="false"
AIRPORTS_TABLE_EXISTS="false"
AIRPORTS_RAW_COUNT=0
COUNTRIES_COUNT=0
TIMEZONES_COUNT=0
AIRPORTS_TABLE_COUNT=0
HAS_FK_COUNTRIES="false"
HAS_FK_TIMEZONES="false"

if [ -f "$AIRPORTS_DB" ]; then
    AIRPORTS_DB_EXISTS="true"

    # Check what tables exist
    TABLES=$(sqlite3 "$AIRPORTS_DB" "SELECT name FROM sqlite_master WHERE type='table'" 2>/dev/null)

    echo "$TABLES" | grep -qi "^countries$" && COUNTRIES_TABLE_EXISTS="true"
    echo "$TABLES" | grep -qi "^timezones$" && TIMEZONES_TABLE_EXISTS="true"
    # Check for 'airports' table that is NOT airports_raw
    echo "$TABLES" | grep -q "^airports$" && AIRPORTS_TABLE_EXISTS="true"

    # Count records in each table
    AIRPORTS_RAW_COUNT=$(sqlite3 "$AIRPORTS_DB" "SELECT COUNT(*) FROM airports_raw" 2>/dev/null || echo 0)

    if [ "$COUNTRIES_TABLE_EXISTS" = "true" ]; then
        COUNTRIES_COUNT=$(sqlite3 "$AIRPORTS_DB" "SELECT COUNT(*) FROM countries" 2>/dev/null || echo 0)
    fi

    if [ "$TIMEZONES_TABLE_EXISTS" = "true" ]; then
        TIMEZONES_COUNT=$(sqlite3 "$AIRPORTS_DB" "SELECT COUNT(*) FROM timezones" 2>/dev/null || echo 0)
    fi

    if [ "$AIRPORTS_TABLE_EXISTS" = "true" ]; then
        AIRPORTS_TABLE_COUNT=$(sqlite3 "$AIRPORTS_DB" "SELECT COUNT(*) FROM airports" 2>/dev/null || echo 0)
    fi

    # Check for FK declarations in schema
    CREATE_SQL=$(sqlite3 "$AIRPORTS_DB" "SELECT sql FROM sqlite_master WHERE type='table' AND name='airports'" 2>/dev/null)
    echo "$CREATE_SQL" | grep -qi "references countries" && HAS_FK_COUNTRIES="true"
    echo "$CREATE_SQL" | grep -qi "references timezones" && HAS_FK_TIMEZONES="true"
fi

# Check validation report
REPORT_EXISTS="false"
REPORT_HAS_ORIGINAL="false"
REPORT_HAS_AIRPORTS="false"
REPORT_HAS_COUNTRIES="false"
REPORT_HAS_TIMEZONES="false"
REPORT_MIGRATION_VALID="false"
REPORT_ORIGINAL_VALUE=0
REPORT_AIRPORTS_VALUE=0

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_FILE")
    echo "$REPORT_CONTENT" | grep -qi "original_count" && REPORT_HAS_ORIGINAL="true"
    echo "$REPORT_CONTENT" | grep -qi "airports_table_count\|airports.*count" && REPORT_HAS_AIRPORTS="true"
    echo "$REPORT_CONTENT" | grep -qi "countries_count\|countries.*count" && REPORT_HAS_COUNTRIES="true"
    echo "$REPORT_CONTENT" | grep -qi "timezones_count\|timezones.*count" && REPORT_HAS_TIMEZONES="true"
    echo "$REPORT_CONTENT" | grep -qi "migration_valid.*yes\|valid.*yes\|migration.*true" && REPORT_MIGRATION_VALID="true"

    # Extract numeric values
    REPORT_ORIGINAL_VALUE=$(echo "$REPORT_CONTENT" | grep -i "original_count" | grep -oE '[0-9]+' | head -1 || echo 0)
    REPORT_AIRPORTS_VALUE=$(echo "$REPORT_CONTENT" | grep -i "airports_table_count\|airports.*count" | grep -oE '[0-9]+' | head -1 || echo 0)
fi

# Read ground truth
GT_ORIGINAL_COUNT=$(cat /tmp/initial_airports_raw_count 2>/dev/null || echo 0)
if [ -f /tmp/airports_normalization_gt.json ]; then
    GT_COUNTRY_COUNT=$(python3 -c "import json; d=json.load(open('/tmp/airports_normalization_gt.json')); print(d.get('country_count',0))" 2>/dev/null || echo 0)
    GT_TZ_COUNT=$(python3 -c "import json; d=json.load(open('/tmp/airports_normalization_gt.json')); print(d.get('timezone_count',0))" 2>/dev/null || echo 0)
else
    GT_COUNTRY_COUNT=0
    GT_TZ_COUNT=0
fi

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo 0)
REPORT_CREATED_AFTER_START="false"
if [ -f "$REPORT_FILE" ]; then
    FILE_TIME=$(stat -c%Y "$REPORT_FILE" 2>/dev/null || stat -f%m "$REPORT_FILE" 2>/dev/null || echo 0)
    [ "$FILE_TIME" -gt "$TASK_START" ] && REPORT_CREATED_AFTER_START="true"
fi

cat > /tmp/airport_schema_result.json << EOF
{
    "airports_conn_found": $AIRPORTS_CONN_FOUND,
    "airports_db_exists": $AIRPORTS_DB_EXISTS,
    "countries_table_exists": $COUNTRIES_TABLE_EXISTS,
    "timezones_table_exists": $TIMEZONES_TABLE_EXISTS,
    "airports_table_exists": $AIRPORTS_TABLE_EXISTS,
    "airports_raw_count": $AIRPORTS_RAW_COUNT,
    "countries_count": $COUNTRIES_COUNT,
    "timezones_count": $TIMEZONES_COUNT,
    "airports_table_count": $AIRPORTS_TABLE_COUNT,
    "has_fk_countries": $HAS_FK_COUNTRIES,
    "has_fk_timezones": $HAS_FK_TIMEZONES,
    "report_exists": $REPORT_EXISTS,
    "report_has_original": $REPORT_HAS_ORIGINAL,
    "report_has_airports": $REPORT_HAS_AIRPORTS,
    "report_has_countries": $REPORT_HAS_COUNTRIES,
    "report_has_timezones": $REPORT_HAS_TIMEZONES,
    "report_migration_valid": $REPORT_MIGRATION_VALID,
    "report_original_value": ${REPORT_ORIGINAL_VALUE:-0},
    "report_airports_value": ${REPORT_AIRPORTS_VALUE:-0},
    "report_created_after_start": $REPORT_CREATED_AFTER_START,
    "gt_original_count": $GT_ORIGINAL_COUNT,
    "gt_country_count": $GT_COUNTRY_COUNT,
    "gt_tz_count": $GT_TZ_COUNT,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result:"
cat /tmp/airport_schema_result.json
echo ""
echo "=== Export Complete ==="
