#!/bin/bash
echo "=== Exporting Volume Migration Results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Helper for JSON output
json_val() {
    echo "$1" | sed 's/ /_/g'
}

# 1. Capture Task Metadata
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TIMESTAMP=$(date -Iseconds)

# 2. Check Container Status
CONTAINER_NAME="employee-db"
IS_RUNNING=0
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    IS_RUNNING=1
fi

# 3. Inspect Mounts (The Critical Check)
MOUNT_TYPE="none"
VOLUME_NAME="none"
SOURCE_PATH="none"

if [ "$IS_RUNNING" -eq 1 ]; then
    # Get the first mount's type and name/source
    # We expect destination /var/lib/postgresql/data
    MOUNT_INFO=$(docker inspect "$CONTAINER_NAME" --format '{{range .Mounts}}{{if eq .Destination "/var/lib/postgresql/data"}}{{.Type}}|{{.Name}}|{{.Source}}{{end}}{{end}}')
    
    if [ -n "$MOUNT_INFO" ]; then
        MOUNT_TYPE=$(echo "$MOUNT_INFO" | cut -d'|' -f1)
        VOLUME_NAME=$(echo "$MOUNT_INFO" | cut -d'|' -f2)
        SOURCE_PATH=$(echo "$MOUNT_INFO" | cut -d'|' -f3)
        
        # If it's a bind mount, Name might be empty, check Source
        if [ "$MOUNT_TYPE" == "bind" ]; then
            VOLUME_NAME="bind_mount"
        fi
    fi
fi

# 4. Check Data Integrity
ROW_COUNT=0
TABLE_EXISTS=0

if [ "$IS_RUNNING" -eq 1 ]; then
    # Use psql to check data
    if docker exec "$CONTAINER_NAME" psql -U postgres -d employees -c '\dt' 2>/dev/null | grep -q "employees"; then
        TABLE_EXISTS=1
        COUNT_RES=$(docker exec "$CONTAINER_NAME" psql -U postgres -d employees -t -c "SELECT COUNT(*) FROM employees;" 2>/dev/null | tr -d '[:space:]')
        if [[ "$COUNT_RES" =~ ^[0-9]+$ ]]; then
            ROW_COUNT=$COUNT_RES
        fi
    fi
fi

# 5. Check docker-compose.yml content (Static Analysis)
COMPOSE_USES_VOLUME=0
COMPOSE_FILE="/home/ga/projects/employee-db/docker-compose.yml"
if [ -f "$COMPOSE_FILE" ]; then
    # Check if 'volumes:' section defines the volume
    if grep -q "employee_db_data:" "$COMPOSE_FILE"; then
        # Check if service uses it (simple grep, not perfect yaml parsing but good heuristic)
        if grep -q "\- employee_db_data:/var/lib/postgresql/data" "$COMPOSE_FILE"; then
            COMPOSE_USES_VOLUME=1
        fi
    fi
fi

# 6. Capture Final Screenshot
take_screenshot /tmp/task_end_screenshot.png 2>/dev/null || true

# 7. Write Result JSON
cat > /tmp/migration_result.json <<EOF
{
    "task_start": $TASK_START,
    "is_running": $IS_RUNNING,
    "mount_type": "$MOUNT_TYPE",
    "volume_name": "$VOLUME_NAME",
    "row_count": $ROW_COUNT,
    "table_exists": $TABLE_EXISTS,
    "compose_uses_volume": $COMPOSE_USES_VOLUME,
    "timestamp": "$TIMESTAMP"
}
EOF

echo "Result Exported:"
cat /tmp/migration_result.json