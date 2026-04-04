#!/bin/bash
echo "=== Exporting convert_db_storage_engine result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DB_NAME="inventory_db"

# ---------------------------------------------------------------
# 1. Capture Final Screenshot
# ---------------------------------------------------------------
take_screenshot /tmp/task_final.png

# ---------------------------------------------------------------
# 2. Inspect Database State
# ---------------------------------------------------------------

# Get current storage engine
FINAL_ENGINE=$(virtualmin_db_query "SELECT ENGINE FROM information_schema.TABLES WHERE TABLE_SCHEMA='${DB_NAME}' AND TABLE_NAME='products';" | tail -1)

# Get current row count
FINAL_ROW_COUNT=$(virtualmin_db_query "SELECT COUNT(*) FROM ${DB_NAME}.products;" | tail -1)

# Get current data hash
FINAL_DATA_HASH=$(virtualmin_db_query "SELECT SUM(LENGTH(name)) + SUM(stock_qty) FROM ${DB_NAME}.products;" | tail -1)

# Retrieve initial values
INITIAL_ROW_COUNT=$(cat /home/ga/initial_row_count.txt 2>/dev/null || echo "0")
INITIAL_DATA_HASH=$(cat /home/ga/initial_data_hash.txt 2>/dev/null || echo "0")

# ---------------------------------------------------------------
# 3. Verify Changes
# ---------------------------------------------------------------

# Check if engine changed
ENGINE_CONVERTED="false"
if [ "$FINAL_ENGINE" == "InnoDB" ]; then
    ENGINE_CONVERTED="true"
fi

# Check if data preserved
DATA_PRESERVED="false"
if [ "$FINAL_ROW_COUNT" -eq "$INITIAL_ROW_COUNT" ] && [ "$FINAL_ROW_COUNT" -gt 0 ]; then
    DATA_PRESERVED="true"
fi

# Check data integrity (hash match)
INTEGRITY_PASSED="false"
if [ "$FINAL_DATA_HASH" == "$INITIAL_DATA_HASH" ] && [ -n "$FINAL_DATA_HASH" ]; then
    INTEGRITY_PASSED="true"
fi

# Check if table modification time is within task window
# We check the .ibd or .MYD file modification time if we were local,
# but querying UPDATE_TIME from information_schema is safer/easier
# Note: InnoDB UPDATE_TIME might be NULL in some configs, so this is a soft check
UPDATE_TIME=$(virtualmin_db_query "SELECT UNIX_TIMESTAMP(UPDATE_TIME) FROM information_schema.TABLES WHERE TABLE_SCHEMA='${DB_NAME}' AND TABLE_NAME='products';" | tail -1)
MODIFIED_DURING_TASK="false"
# If UPDATE_TIME is null (common for InnoDB), we rely on the state change itself
if [ "$UPDATE_TIME" != "NULL" ] && [ -n "$UPDATE_TIME" ]; then
    if [ "$UPDATE_TIME" -ge "$TASK_START" ]; then
        MODIFIED_DURING_TASK="true"
    fi
else
    # Fallback: if engine changed from MyISAM to InnoDB, it WAS modified
    if [ "$FINAL_ENGINE" == "InnoDB" ]; then
        MODIFIED_DURING_TASK="true"
    fi
fi

# ---------------------------------------------------------------
# 4. Generate Result JSON
# ---------------------------------------------------------------
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_row_count": $INITIAL_ROW_COUNT,
    "final_row_count": $FINAL_ROW_COUNT,
    "final_engine": "$FINAL_ENGINE",
    "engine_converted": $ENGINE_CONVERTED,
    "data_preserved": $DATA_PRESERVED,
    "integrity_passed": $INTEGRITY_PASSED,
    "modified_during_task": $MODIFIED_DURING_TASK,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with safe permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="