#!/bin/bash
# Export script for world_data_import_functions task

echo "=== Exporting World Data Import Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
EXPORT_FILE="/home/ga/Documents/exports/country_analysis.csv"

# --- 1. Database Structure Verification ---

# Check if database exists
DB_EXISTS=$(mysql -u root -p'GymAnything#2024' -N -e "SELECT COUNT(*) FROM information_schema.SCHEMATA WHERE SCHEMA_NAME = 'world_analytics';" 2>/dev/null || echo "0")

# Check if table exists and row count
TABLE_EXISTS=0
ROW_COUNT=0
if [ "$DB_EXISTS" -eq 1 ]; then
    TABLE_EXISTS=$(mysql -u root -p'GymAnything#2024' -N -e "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = 'world_analytics' AND TABLE_NAME = 'country_indicators';" 2>/dev/null || echo "0")
    if [ "$TABLE_EXISTS" -eq 1 ]; then
        ROW_COUNT=$(mysql -u root -p'GymAnything#2024' -N -e "SELECT COUNT(*) FROM world_analytics.country_indicators;" 2>/dev/null || echo "0")
    fi
fi

# Check columns (verify schema accuracy)
COLUMNS_MATCH=0
if [ "$TABLE_EXISTS" -eq 1 ]; then
    EXPECTED_COLS="id CountryCode CountryName Population SurfaceArea GNP LifeExpectancy PopulationDensity GNPPerCapita"
    ACTUAL_COLS=$(mysql -u root -p'GymAnything#2024' -N -e "SELECT COLUMN_NAME FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = 'world_analytics' AND TABLE_NAME = 'country_indicators' ORDER BY ORDINAL_POSITION;" 2>/dev/null | tr '\n' ' ')
    
    # Simple check if all expected columns are present
    MISSING_COL=0
    for col in $EXPECTED_COLS; do
        if [[ ! "$ACTUAL_COLS" =~ "$col" ]]; then
            MISSING_COL=1
        fi
    done
    if [ "$MISSING_COL" -eq 0 ]; then
        COLUMNS_MATCH=1
    fi
fi

# Check Foreign Key
FK_EXISTS=$(mysql -u root -p'GymAnything#2024' -N -e "
    SELECT COUNT(*) FROM information_schema.KEY_COLUMN_USAGE 
    WHERE TABLE_SCHEMA = 'world_analytics' 
    AND TABLE_NAME = 'country_indicators' 
    AND COLUMN_NAME = 'CountryCode' 
    AND REFERENCED_TABLE_SCHEMA = 'world' 
    AND REFERENCED_TABLE_NAME = 'country' 
    AND REFERENCED_COLUMN_NAME = 'Code';
" 2>/dev/null || echo "0")


# --- 2. Function Logic Verification ---
# We test the functions directly if they exist
FUNC_DEV_TEST=""
FUNC_DENS_TEST=""
FUNC_EXISTS=0

# Check if functions exist
FN_DEV_EXISTS=$(mysql -u root -p'GymAnything#2024' -N -e "SELECT COUNT(*) FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA='world_analytics' AND ROUTINE_NAME='fn_development_level';" 2>/dev/null || echo "0")
FN_DENS_EXISTS=$(mysql -u root -p'GymAnything#2024' -N -e "SELECT COUNT(*) FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA='world_analytics' AND ROUTINE_NAME='fn_density_category';" 2>/dev/null || echo "0")

if [ "$FN_DEV_EXISTS" -eq 1 ]; then
    # Test High, Medium, Low
    FUNC_DEV_TEST=$(mysql -u root -p'GymAnything#2024' -N -e "SELECT CONCAT(world_analytics.fn_development_level(15000), ',', world_analytics.fn_development_level(5000), ',', world_analytics.fn_development_level(500));" 2>/dev/null)
fi

if [ "$FN_DENS_EXISTS" -eq 1 ]; then
    # Test Dense, Moderate, Sparse
    FUNC_DENS_TEST=$(mysql -u root -p'GymAnything#2024' -N -e "SELECT CONCAT(world_analytics.fn_density_category(300), ',', world_analytics.fn_density_category(100), ',', world_analytics.fn_density_category(10));" 2>/dev/null)
fi


# --- 3. View Verification ---
VIEW_EXISTS=$(mysql -u root -p'GymAnything#2024' -N -e "SELECT COUNT(*) FROM information_schema.VIEWS WHERE TABLE_SCHEMA='world_analytics' AND TABLE_NAME='v_country_analysis';" 2>/dev/null || echo "0")
VIEW_ROWS=0
if [ "$VIEW_EXISTS" -eq 1 ]; then
    VIEW_ROWS=$(mysql -u root -p'GymAnything#2024' -N -e "SELECT COUNT(*) FROM world_analytics.v_country_analysis;" 2>/dev/null || echo "0")
fi


# --- 4. Export File Verification ---
FILE_EXISTS="false"
FILE_ROWS=0
FILE_MTIME=0
CREATED_DURING_TASK="false"

if [ -f "$EXPORT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_ROWS=$(count_csv_lines "$EXPORT_FILE")
    FILE_MTIME=$(stat -c %Y "$EXPORT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi
fi

# --- 5. Generate JSON Result ---
cat > /tmp/task_result.json << EOF
{
    "db_exists": $DB_EXISTS,
    "table_exists": $TABLE_EXISTS,
    "row_count": $ROW_COUNT,
    "columns_match": $COLUMNS_MATCH,
    "fk_exists": $FK_EXISTS,
    "fn_dev_exists": $FN_DEV_EXISTS,
    "fn_dev_test_result": "$FUNC_DEV_TEST",
    "fn_dens_exists": $FN_DENS_EXISTS,
    "fn_dens_test_result": "$FUNC_DENS_TEST",
    "view_exists": $VIEW_EXISTS,
    "view_rows": $VIEW_ROWS,
    "file_exists": $FILE_EXISTS,
    "file_rows": $FILE_ROWS,
    "file_created_during_task": $CREATED_DURING_TASK,
    "task_start_time": $TASK_START
}
EOF

echo "Result JSON generated at /tmp/task_result.json"
cat /tmp/task_result.json