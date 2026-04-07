#!/bin/bash
# Export script for world_regional_analysis_schema task

echo "=== Exporting World Regional Analysis Result ==="

source /workspace/scripts/task_utils.sh

if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Database Credentials
DB_USER="ga"
DB_PASS="password123"
DB_NAME="world_regions"

# Helper to run SQL
run_sql() {
    mysql -u "$DB_USER" -p"$DB_PASS" -N -e "$1" 2>/dev/null
}

# 1. Check Database Existence
DB_EXISTS=$(mysql -u "$DB_USER" -p"$DB_PASS" -e "USE $DB_NAME" 2>/dev/null && echo "true" || echo "false")

# 2. Check Table Counts & Structure
CNT_CONTINENTS=0
CNT_REGIONS=0
CNT_COUNTRIES=0
CNT_AUDIT=0
AUDIT_HAS_USA=0
CONTINENTS_HAS_7=0

if [ "$DB_EXISTS" = "true" ]; then
    # Continents
    CNT_CONTINENTS=$(run_sql "SELECT COUNT(*) FROM $DB_NAME.continents")
    CNT_CONTINENTS=${CNT_CONTINENTS:-0}
    if [ "$CNT_CONTINENTS" -eq 7 ]; then CONTINENTS_HAS_7="true"; else CONTINENTS_HAS_7="false"; fi

    # Regions
    CNT_REGIONS=$(run_sql "SELECT COUNT(*) FROM $DB_NAME.regions")
    CNT_REGIONS=${CNT_REGIONS:-0}

    # Country Stats
    CNT_COUNTRIES=$(run_sql "SELECT COUNT(*) FROM $DB_NAME.country_stats")
    CNT_COUNTRIES=${CNT_COUNTRIES:-0}

    # Audit Table
    CNT_AUDIT_TABLE_EXISTS=$(run_sql "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$DB_NAME' AND table_name='country_audit'")
    if [ "$CNT_AUDIT_TABLE_EXISTS" -eq 1 ]; then
        # Check if Trigger Fired (Audit record for USA population)
        AUDIT_HAS_USA=$(run_sql "SELECT COUNT(*) FROM $DB_NAME.country_audit WHERE country_code='USA' AND field_changed='population'")
        AUDIT_HAS_USA=${AUDIT_HAS_USA:-0}
    fi
fi

# 3. Check Foreign Keys
# We expect regions -> continents and country_stats -> regions
FK_REGIONS=0
FK_COUNTRIES=0

if [ "$DB_EXISTS" = "true" ]; then
    FK_REGIONS=$(run_sql "SELECT COUNT(*) FROM information_schema.KEY_COLUMN_USAGE WHERE TABLE_SCHEMA='$DB_NAME' AND TABLE_NAME='regions' AND REFERENCED_TABLE_NAME='continents'")
    FK_COUNTRIES=$(run_sql "SELECT COUNT(*) FROM information_schema.KEY_COLUMN_USAGE WHERE TABLE_SCHEMA='$DB_NAME' AND TABLE_NAME='country_stats' AND REFERENCED_TABLE_NAME='regions'")
fi

# 4. Check Stored Function & Trigger Existence
HAS_TRIGGER=0
HAS_FUNCTION=0
FUNCTION_RESULT="0.0"

if [ "$DB_EXISTS" = "true" ]; then
    HAS_TRIGGER=$(run_sql "SELECT COUNT(*) FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA='$DB_NAME' AND TRIGGER_NAME='trg_country_population_audit'")
    HAS_FUNCTION=$(run_sql "SELECT COUNT(*) FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA='$DB_NAME' AND ROUTINE_NAME='fn_continent_avg_life_expectancy'")

    # Test Function if it exists
    if [ "$HAS_FUNCTION" -gt 0 ]; then
        FUNCTION_RESULT=$(run_sql "SELECT $DB_NAME.fn_continent_avg_life_expectancy('Europe')")
        FUNCTION_RESULT=${FUNCTION_RESULT:-0}
    fi
fi

# 5. Check CSV Export
CSV_PATH="/home/ga/Documents/exports/top20_countries.csv"
CSV_EXISTS="false"
CSV_ROWS=0
CSV_CREATED_DURING_TASK="false"

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    # Check timestamp
    FILE_TIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_TIME" -gt "$TASK_START" ]; then
        CSV_CREATED_DURING_TASK="true"
    fi
    # Check rows (header + 20 data rows = 21 lines)
    TOTAL_LINES=$(wc -l < "$CSV_PATH" || echo "0")
    CSV_ROWS=$((TOTAL_LINES - 1)) # subtract header
fi

# Create Result JSON
cat > /tmp/task_result.json << EOF
{
    "db_exists": $DB_EXISTS,
    "cnt_continents": $CNT_CONTINENTS,
    "continents_correct_count": $CONTINENTS_HAS_7,
    "cnt_regions": $CNT_REGIONS,
    "cnt_countries": $CNT_COUNTRIES,
    "audit_record_count": $AUDIT_HAS_USA,
    "fk_regions_exists": $FK_REGIONS,
    "fk_countries_exists": $FK_COUNTRIES,
    "has_trigger": $HAS_TRIGGER,
    "has_function": $HAS_FUNCTION,
    "function_result_europe": "$FUNCTION_RESULT",
    "csv_exists": $CSV_EXISTS,
    "csv_rows": $CSV_ROWS,
    "csv_fresh": $CSV_CREATED_DURING_TASK
}
EOF

chmod 666 /tmp/task_result.json

echo "Export complete. JSON generated."
cat /tmp/task_result.json