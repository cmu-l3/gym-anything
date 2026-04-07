#!/bin/bash
# Export script for sakila_schema_drift_remediation

echo "=== Exporting Result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check Script Artifact
SCRIPT_PATH="/home/ga/Documents/sql_scripts/revert_drift.sql"
SCRIPT_EXISTS="false"
SCRIPT_SIZE=0
if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_EXISTS="true"
    SCRIPT_SIZE=$(stat -c%s "$SCRIPT_PATH")
fi

# 3. Check Live Data Preservation (Anti-Gaming)
# We check if the unique record we inserted in setup still exists
TRACER_RENTAL_ID=$(cat /tmp/tracer_rental_id.txt 2>/dev/null || echo "999999")
LIVE_DATA_EXISTS="false"
CHECK_DATA=$(mysql -u root -p'GymAnything#2024' sakila_prod -N -e "SELECT COUNT(*) FROM rental WHERE rental_id = '$TRACER_RENTAL_ID'" 2>/dev/null)

if [ "$CHECK_DATA" -eq "1" ]; then
    LIVE_DATA_EXISTS="true"
fi

# 4. Verify Schema States (The Core Task)

# 4a. Check Customer Table (last_name length)
# Expected: varchar(45) (Gold state)
# Drifted was: varchar(100)
CUSTOMER_COL_TYPE=$(mysql -u root -p'GymAnything#2024' information_schema -N -e "
    SELECT COLUMN_TYPE FROM COLUMNS 
    WHERE TABLE_SCHEMA='sakila_prod' AND TABLE_NAME='customer' AND COLUMN_NAME='last_name'
")

# 4b. Check Address Index
# Expected: idx_fk_city_id exists
ADDRESS_IDX_COUNT=$(mysql -u root -p'GymAnything#2024' information_schema -N -e "
    SELECT COUNT(*) FROM STATISTICS 
    WHERE TABLE_SCHEMA='sakila_prod' AND TABLE_NAME='address' AND INDEX_NAME='idx_fk_city_id'
")

# 4c. Check Store Column
# Expected: internal_notes does NOT exist
STORE_COL_COUNT=$(mysql -u root -p'GymAnything#2024' information_schema -N -e "
    SELECT COUNT(*) FROM COLUMNS 
    WHERE TABLE_SCHEMA='sakila_prod' AND TABLE_NAME='store' AND COLUMN_NAME='internal_notes'
")

# 4d. Check View Definition
# Expected: View should contain 'country' column again
VIEW_HAS_COUNTRY=$(mysql -u root -p'GymAnything#2024' information_schema -N -e "
    SELECT COUNT(*) FROM COLUMNS 
    WHERE TABLE_SCHEMA='sakila_prod' AND TABLE_NAME='customer_list' AND COLUMN_NAME='country'
")

# 5. Check timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILE_MTIME=0
if [ -f "$SCRIPT_PATH" ]; then
    FILE_MTIME=$(stat -c%Y "$SCRIPT_PATH")
fi

# 6. Generate JSON
cat > /tmp/task_result.json << EOF
{
    "script_exists": $SCRIPT_EXISTS,
    "script_size": $SCRIPT_SIZE,
    "file_mtime": $FILE_MTIME,
    "task_start": $TASK_START,
    "live_data_preserved": $LIVE_DATA_EXISTS,
    "customer_col_type": "$CUSTOMER_COL_TYPE",
    "address_idx_count": $ADDRESS_IDX_COUNT,
    "store_col_count": $STORE_COL_COUNT,
    "view_has_country": $VIEW_HAS_COUNTRY
}
EOF

echo "Export complete. Result:"
cat /tmp/task_result.json