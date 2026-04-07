#!/bin/bash
# Export script for docker_compose_merge task

echo "=== Exporting Docker Compose Merge Results ==="
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
take_screenshot /tmp/task_final.png

MERGED_DIR="/home/ga/projects/merged"
COMPOSE_FILE="$MERGED_DIR/docker-compose.yml"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Check if compose file exists
COMPOSE_EXISTS="false"
if [ -f "$COMPOSE_FILE" ]; then
    COMPOSE_EXISTS="true"
fi

# 2. Get running services from the merged project
# We use the project directory name 'merged' (default project name)
PROJECT_NAME="merged"
RUNNING_CONTAINERS=$(docker compose -p "$PROJECT_NAME" ps --status running --format '{{.Service}}')
RUNNING_COUNT=$(echo "$RUNNING_CONTAINERS" | grep -v "^$" | wc -l)

echo "Running containers count: $RUNNING_COUNT"

# 3. Analyze Ports and Service Mapping
# We need to find which container maps to which original service function
# Strategy: Inspect images and env vars

AUTH_API_STATUS="missing"
CATALOG_API_STATUS="missing"
AUTH_DB_STATUS="missing"
CATALOG_DB_STATUS="missing"
REDIS_STATUS="missing"
SEARCH_STATUS="missing"

AUTH_API_PORT="0"
CATALOG_API_PORT="0"
AUTH_API_URL=""
CATALOG_API_URL=""

# List all container IDs in the merged project
CONTAINER_IDS=$(docker compose -p "$PROJECT_NAME" ps -q)

for cid in $CONTAINER_IDS; do
    IMAGE=$(docker inspect --format '{{.Config.Image}}' $cid)
    CMD=$(docker inspect --format '{{json .Config.Cmd}}' $cid)
    ENV=$(docker inspect --format '{{json .Config.Env}}' $cid)
    STATE=$(docker inspect --format '{{.State.Status}}' $cid)
    
    # Identify Service
    if [[ "$IMAGE" == *"acme-auth-api"* ]]; then
        AUTH_API_STATUS="$STATE"
        # Get host port
        # .NetworkSettings.Ports["5000/tcp"][0].HostPort
        PORT=$(docker inspect --format '{{(index (index .NetworkSettings.Ports "5000/tcp") 0).HostPort}}' $cid 2>/dev/null || echo "0")
        AUTH_API_PORT="$PORT"
        AUTH_API_URL="http://localhost:$PORT"
    elif [[ "$IMAGE" == *"acme-catalog-api"* ]]; then
        CATALOG_API_STATUS="$STATE"
        PORT=$(docker inspect --format '{{(index (index .NetworkSettings.Ports "3000/tcp") 0).HostPort}}' $cid 2>/dev/null || echo "0")
        CATALOG_API_PORT="$PORT"
        CATALOG_API_URL="http://localhost:$PORT"
    elif [[ "$IMAGE" == *"redis"* ]]; then
        REDIS_STATUS="$STATE"
    elif [[ "$IMAGE" == *"postgres"* ]]; then
        # Distinguish DBs by env vars
        if echo "$ENV" | grep -q "authdb"; then
            AUTH_DB_STATUS="$STATE"
        elif echo "$ENV" | grep -q "catalogdb"; then
            CATALOG_DB_STATUS="$STATE"
        fi
    elif [[ "$IMAGE" == *"alpine"* ]] && echo "$CMD" | grep -q "socat"; then
        SEARCH_STATUS="$STATE"
    fi
done

# 4. Functional Testing (Health Checks)
AUTH_API_HEALTH="failed"
AUTH_API_RESPONSE=""
if [ "$AUTH_API_PORT" != "0" ] && [ "$AUTH_API_STATUS" == "running" ]; then
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$AUTH_API_URL/health")
    if [ "$HTTP_CODE" == "200" ]; then
        AUTH_API_HEALTH="passed"
        AUTH_API_RESPONSE=$(curl -s "$AUTH_API_URL/health")
    fi
fi

CATALOG_API_HEALTH="failed"
CATALOG_API_RESPONSE=""
if [ "$CATALOG_API_PORT" != "0" ] && [ "$CATALOG_API_STATUS" == "running" ]; then
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$CATALOG_API_URL/health")
    if [ "$HTTP_CODE" == "200" ]; then
        CATALOG_API_HEALTH="passed"
        CATALOG_API_RESPONSE=$(curl -s "$CATALOG_API_URL/health")
    fi
fi

# 5. Check for conflicts
# Check if unique ports
PORTS_UNIQUE="false"
if [ "$AUTH_API_PORT" != "$CATALOG_API_PORT" ] && [ "$AUTH_API_PORT" != "0" ] && [ "$CATALOG_API_PORT" != "0" ]; then
    PORTS_UNIQUE="true"
fi

# Check service names in compose file
UNIQUE_SERVICE_NAMES="true"
if [ -f "$COMPOSE_FILE" ]; then
    SERVICE_NAMES=$(grep "^  [a-zA-Z0-9_-]*:" "$COMPOSE_FILE" | tr -d ' :')
    DUPLICATES=$(echo "$SERVICE_NAMES" | sort | uniq -d)
    if [ -n "$DUPLICATES" ]; then
        UNIQUE_SERVICE_NAMES="false"
    fi
    
    # Check if 'db' is still used as a service name (ambiguous)
    if echo "$SERVICE_NAMES" | grep -q "^db$"; then
        # It's technically allowed if only one db uses it, but in a merge it's bad practice if both needed it.
        # We'll rely on the count of running dbs to ensure both are up.
        true
    fi
fi

# 6. Create Result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "compose_file_exists": $COMPOSE_EXISTS,
    "running_services_count": $RUNNING_COUNT,
    "services_status": {
        "auth_api": "$AUTH_API_STATUS",
        "catalog_api": "$CATALOG_API_STATUS",
        "auth_db": "$AUTH_DB_STATUS",
        "catalog_db": "$CATALOG_DB_STATUS",
        "redis": "$REDIS_STATUS",
        "search": "$SEARCH_STATUS"
    },
    "ports": {
        "auth_api": "$AUTH_API_PORT",
        "catalog_api": "$CATALOG_API_PORT"
    },
    "health_checks": {
        "auth_api": "$AUTH_API_HEALTH",
        "catalog_api": "$CATALOG_API_HEALTH"
    },
    "unique_ports": $PORTS_UNIQUE,
    "unique_service_names": $UNIQUE_SERVICE_NAMES,
    "responses": {
        "auth": "$(json_escape "$AUTH_API_RESPONSE")",
        "catalog": "$(json_escape "$CATALOG_API_RESPONSE")"
    }
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="