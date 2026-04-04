#!/bin/bash
# Export script for debug_postgres_init_failure
# Checks if the database is running, if the table exists, and if the init script actually ran.

echo "=== Exporting debug_postgres_init_failure result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Variables
CONTAINER_NAME="inventory_db"
VOLUME_NAME="inventory_pgdata"
EXPECTED_TABLE="products"

# 1. Check if Container is Running
CONTAINER_RUNNING="false"
if [ "$(docker inspect -f '{{.State.Running}}' $CONTAINER_NAME 2>/dev/null)" == "true" ]; then
    CONTAINER_RUNNING="true"
fi

# 2. Check if Table Exists
TABLE_EXISTS="false"
TABLE_COUNT="-1"

if [ "$CONTAINER_RUNNING" == "true" ]; then
    # Query Postgres for the table existence
    if docker exec $CONTAINER_NAME psql -U postgres -d inventory -tAc "SELECT 1 FROM information_schema.tables WHERE table_name = '$EXPECTED_TABLE';" 2>/dev/null | grep -q "1"; then
        TABLE_EXISTS="true"
        # Optional: Check row count
        TABLE_COUNT=$(docker exec $CONTAINER_NAME psql -U postgres -d inventory -tAc "SELECT count(*) FROM $EXPECTED_TABLE;" 2>/dev/null || echo "0")
    fi
fi

# 3. Check logs for Automatic Init Script Execution
# This verifies the agent actually fixed the volume issue rather than just running SQL manually
INIT_SCRIPT_RAN_AUTOMATICALLY="false"
if [ "$CONTAINER_RUNNING" == "true" ]; then
    # The official postgres image logs this specific line when running init scripts
    if docker logs $CONTAINER_NAME 2>&1 | grep -q "/docker-entrypoint-initdb.d/init.sql"; then
        INIT_SCRIPT_RAN_AUTOMATICALLY="true"
    fi
fi

# 4. Check Volume Recreation Time (Anti-Gaming / Confirmation)
# We expect the volume to be newer than the task start time
VOLUME_RECREATED="false"
VOLUME_CREATED_AT=$(docker volume inspect $VOLUME_NAME -f '{{.CreatedAt}}' 2>/dev/null)

# Convert ISO8601 to timestamp for comparison (requires date parsing support)
# Fallback: We rely primarily on the logs check, but this is good metadata
if [ -n "$VOLUME_CREATED_AT" ]; then
    # Docker returns time like "2023-10-27T10:00:00Z"
    VOL_TS=$(date -d "$VOLUME_CREATED_AT" +%s 2>/dev/null || echo "0")
    if [ "$VOL_TS" -gt "$TASK_START" ]; then
        VOLUME_RECREATED="true"
    fi
fi

# 5. Check if Docker Desktop is running
DOCKER_DESKTOP_RUNNING="false"
if docker_desktop_running; then
    DOCKER_DESKTOP_RUNNING="true"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "container_running": $CONTAINER_RUNNING,
    "table_exists": $TABLE_EXISTS,
    "row_count": $TABLE_COUNT,
    "init_script_ran_automatically": $INIT_SCRIPT_RAN_AUTOMATICALLY,
    "volume_recreated": $VOLUME_RECREATED,
    "docker_desktop_running": $DOCKER_DESKTOP_RUNNING,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="