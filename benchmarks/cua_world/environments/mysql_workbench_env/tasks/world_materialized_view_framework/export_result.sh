#!/bin/bash
# Export script for world_materialized_view_framework task

echo "=== Exporting World Materialized View Framework Result ==="

source /workspace/scripts/task_utils.sh

# Snapshot final state
take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
DB_USER="root"
DB_PASS="GymAnything#2024"
DB_NAME="world"

# 1. Check Table Existence and Column Structure
echo "Checking table structure..."
TABLE_EXISTS=$(mysql -u $DB_USER -p$DB_PASS information_schema -N -e "
    SELECT COUNT(*) FROM TABLES 
    WHERE TABLE_SCHEMA='$DB_NAME' AND TABLE_NAME='mv_country_stats'
")
TABLE_EXISTS=${TABLE_EXISTS:-0}

COLUMN_CHECK=$(mysql -u $DB_USER -p$DB_PASS information_schema -N -e "
    SELECT GROUP_CONCAT(COLUMN_NAME) FROM COLUMNS 
    WHERE TABLE_SCHEMA='$DB_NAME' AND TABLE_NAME='mv_country_stats'
")

# Check for required columns
HAS_REQUIRED_COLS="true"
REQUIRED_COLS=("country_code" "gnp_per_capita" "population_density" "city_count" "language_count" "largest_city_name" "last_refreshed")
for col in "${REQUIRED_COLS[@]}"; do
    if [[ "$COLUMN_CHECK" != *"$col"* ]]; then
        HAS_REQUIRED_COLS="false"
        echo "Missing column: $col"
    fi
done

# 2. Check Row Count
ROW_COUNT=0
if [ "$TABLE_EXISTS" -eq 1 ]; then
    ROW_COUNT=$(mysql -u $DB_USER -p$DB_PASS $DB_NAME -N -e "SELECT COUNT(*) FROM mv_country_stats")
fi
ROW_COUNT=${ROW_COUNT:-0}

# 3. Check Procedure Existence
PROC_EXISTS=$(mysql -u $DB_USER -p$DB_PASS information_schema -N -e "
    SELECT COUNT(*) FROM ROUTINES 
    WHERE ROUTINE_SCHEMA='$DB_NAME' AND ROUTINE_NAME='sp_refresh_country_stats' AND ROUTINE_TYPE='PROCEDURE'
")
PROC_EXISTS=${PROC_EXISTS:-0}

# 4. Check Index Existence
INDEX_EXISTS=$(mysql -u $DB_USER -p$DB_PASS information_schema -N -e "
    SELECT COUNT(*) FROM STATISTICS 
    WHERE TABLE_SCHEMA='$DB_NAME' AND TABLE_NAME='mv_country_stats' AND INDEX_NAME='idx_mv_continent'
")
INDEX_EXISTS=${INDEX_EXISTS:-0}

# 5. Check CSV Export
EXPORT_FILE="/home/ga/Documents/exports/country_stats.csv"
CSV_EXISTS="false"
CSV_SIZE=0
CSV_ROWS=0
CSV_MTIME=0

if [ -f "$EXPORT_FILE" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c%s "$EXPORT_FILE" 2>/dev/null || echo "0")
    CSV_MTIME=$(stat -c%Y "$EXPORT_FILE" 2>/dev/null || echo "0")
    # Count rows, subtract header
    TOTAL_LINES=$(wc -l < "$EXPORT_FILE" 2>/dev/null || echo "0")
    CSV_ROWS=$((TOTAL_LINES - 1))
    [ "$CSV_ROWS" -lt 0 ] && CSV_ROWS=0
fi

# 6. Data Validation (Spot Checks)
# We probe the actual table to verify calculations
USA_STATS="{}"
JPN_STATS="{}"
ATA_STATS="{}"

if [ "$TABLE_EXISTS" -eq 1 ] && [ "$ROW_COUNT" -gt 0 ]; then
    # Helper to get JSON object for a country
    get_country_stats() {
        local code=$1
        mysql -u $DB_USER -p$DB_PASS $DB_NAME -N -e "
            SELECT JSON_OBJECT(
                'gnp_per_capita', gnp_per_capita,
                'population_density', population_density,
                'city_count', city_count,
                'language_count', language_count,
                'largest_city_name', largest_city_name,
                'largest_city_population', largest_city_population
            )
            FROM mv_country_stats WHERE country_code='$code'
        " 2>/dev/null
    }
    
    USA_STATS=$(get_country_stats "USA")
    JPN_STATS=$(get_country_stats "JPN")
    ATA_STATS=$(get_country_stats "ATA")
fi

# Default to empty JSON if query returned nothing
[ -z "$USA_STATS" ] && USA_STATS="{}"
[ -z "$JPN_STATS" ] && JPN_STATS="{}"
[ -z "$ATA_STATS" ] && ATA_STATS="{}"

# Create JSON result
cat > /tmp/mv_result.json << EOF
{
    "table_exists": $TABLE_EXISTS,
    "has_required_cols": $HAS_REQUIRED_COLS,
    "row_count": $ROW_COUNT,
    "proc_exists": $PROC_EXISTS,
    "index_exists": $INDEX_EXISTS,
    "csv_exists": $CSV_EXISTS,
    "csv_rows": $CSV_ROWS,
    "csv_mtime": $CSV_MTIME,
    "task_start": $TASK_START,
    "usa_stats": $USA_STATS,
    "jpn_stats": $JPN_STATS,
    "ata_stats": $ATA_STATS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/mv_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json