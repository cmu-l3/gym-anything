#!/bin/bash
# Export script for world_schema_evolution_computed task

echo "=== Exporting World Schema Evolution Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
DB_USER="ga"
DB_PASS="password123"
DB_NAME="world"

# Helper to run SQL
run_sql() {
    mysql -u "$DB_USER" -p"$DB_PASS" -N -e "$1" "$DB_NAME" 2>/dev/null
}

echo "Verifying Schema Changes..."

# 1. Verify Generated Columns
# Check for gdp_per_capita
COL_GDP_INFO=$(mysql -u "$DB_USER" -p"$DB_PASS" -N -e "
    SELECT EXTRA, GENERATION_EXPRESSION FROM information_schema.COLUMNS 
    WHERE TABLE_SCHEMA='$DB_NAME' AND TABLE_NAME='country' AND COLUMN_NAME='gdp_per_capita'
" 2>/dev/null)

GDP_EXISTS="false"
GDP_IS_GENERATED="false"
if [ -n "$COL_GDP_INFO" ]; then
    GDP_EXISTS="true"
    if echo "$COL_GDP_INFO" | grep -qi "GENERATED"; then
        GDP_IS_GENERATED="true"
    fi
fi

# Check for population_density
COL_POP_INFO=$(mysql -u "$DB_USER" -p"$DB_PASS" -N -e "
    SELECT EXTRA, GENERATION_EXPRESSION FROM information_schema.COLUMNS 
    WHERE TABLE_SCHEMA='$DB_NAME' AND TABLE_NAME='country' AND COLUMN_NAME='population_density'
" 2>/dev/null)

POP_EXISTS="false"
POP_IS_GENERATED="false"
if [ -n "$COL_POP_INFO" ]; then
    POP_EXISTS="true"
    if echo "$COL_POP_INFO" | grep -qi "GENERATED"; then
        POP_IS_GENERATED="true"
    fi
fi

# 2. Verify continent_stats table
STATS_TABLE_EXISTS="false"
STATS_ROW_COUNT=0
STATS_TOTAL_POP=0

if run_sql "SHOW TABLES LIKE 'continent_stats'" | grep -q "continent_stats"; then
    STATS_TABLE_EXISTS="true"
    STATS_ROW_COUNT=$(run_sql "SELECT COUNT(*) FROM continent_stats")
    STATS_TOTAL_POP=$(run_sql "SELECT SUM(total_population) FROM continent_stats")
fi

# 3. Verify Stored Function
FUNC_EXISTS="false"
FUNC_TEST_RESULT=""

if run_sql "SHOW FUNCTION STATUS WHERE Name='fn_classify_development'" | grep -q "fn_classify_development"; then
    FUNC_EXISTS="true"
    # Test the function
    FUNC_TEST_RESULT=$(run_sql "SELECT fn_classify_development(20000)") # Should be 'High'
fi

# 4. Verify View
VIEW_EXISTS="false"
VIEW_ROW_COUNT=0
VIEW_HAS_CLASS_COL="false"

if run_sql "SHOW TABLES LIKE 'v_country_development_profile'" | grep -q "v_country_development_profile"; then
    # Check if it's actually a view
    IS_VIEW=$(mysql -u "$DB_USER" -p"$DB_PASS" -N -e "SELECT TABLE_TYPE FROM information_schema.TABLES WHERE TABLE_SCHEMA='$DB_NAME' AND TABLE_NAME='v_country_development_profile'" 2>/dev/null)
    if [ "$IS_VIEW" = "VIEW" ]; then
        VIEW_EXISTS="true"
        VIEW_ROW_COUNT=$(run_sql "SELECT COUNT(*) FROM v_country_development_profile")
        # Check for column
        if run_sql "SHOW COLUMNS FROM v_country_development_profile LIKE 'development_class'" | grep -q "development_class"; then
            VIEW_HAS_CLASS_COL="true"
        fi
    fi
fi

# 5. Verify CSV Export
CSV_FILE="/home/ga/Documents/exports/country_development_profile.csv"
CSV_EXISTS="false"
CSV_ROWS=0
CSV_MTIME=0

if [ -f "$CSV_FILE" ]; then
    CSV_EXISTS="true"
    CSV_MTIME=$(stat -c%Y "$CSV_FILE" 2>/dev/null || echo "0")
    # Count rows excluding header
    TOTAL_LINES=$(wc -l < "$CSV_FILE" 2>/dev/null || echo "0")
    CSV_ROWS=$((TOTAL_LINES - 1))
    [ "$CSV_ROWS" -lt 0 ] && CSV_ROWS=0
fi

# Generate Result JSON
cat > /tmp/schema_evolution_result.json << EOF
{
    "task_start": $TASK_START,
    "gdp_col_exists": $GDP_EXISTS,
    "gdp_col_generated": $GDP_IS_GENERATED,
    "pop_col_exists": $POP_EXISTS,
    "pop_col_generated": $POP_IS_GENERATED,
    "stats_table_exists": $STATS_TABLE_EXISTS,
    "stats_row_count": ${STATS_ROW_COUNT:-0},
    "stats_total_pop": ${STATS_TOTAL_POP:-0},
    "func_exists": $FUNC_EXISTS,
    "func_test_result": "$FUNC_TEST_RESULT",
    "view_exists": $VIEW_EXISTS,
    "view_row_count": ${VIEW_ROW_COUNT:-0},
    "view_has_class_col": $VIEW_HAS_CLASS_COL,
    "csv_exists": $CSV_EXISTS,
    "csv_rows": $CSV_ROWS,
    "csv_mtime": $CSV_MTIME,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Export complete. Result saved to /tmp/schema_evolution_result.json"
cat /tmp/schema_evolution_result.json