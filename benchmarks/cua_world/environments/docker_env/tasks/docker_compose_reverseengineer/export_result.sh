#!/bin/bash
echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

PROJECT_DIR="/home/ga/projects/inventory-tracker"
COMPOSE_FILE="$PROJECT_DIR/docker-compose.yml"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check Compose File
COMPOSE_EXISTS="false"
VALID_YAML="false"
if [ -f "$COMPOSE_FILE" ]; then
    COMPOSE_EXISTS="true"
    # Basic YAML validation via python
    if python3 -c "import yaml; yaml.safe_load(open('$COMPOSE_FILE'))" 2>/dev/null; then
        VALID_YAML="true"
    fi
fi

# 2. Check Service Functionality
API_ITEMS_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/api/items 2>/dev/null || echo "000")
API_STATUS_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/api/status 2>/dev/null || echo "000")

# 3. Inspect CURRENT running containers
# We expect the agent to have stopped the old ones and started new ones
# We look for containers that are likely the new ones (based on image names)

# Helper to inspect a running container by likely name or image
# We will check if the containers running NOW match the required specs

# Find the container ID currently serving port 8080
WEB_CONTAINER_ID=$(docker ps --format '{{.ID}}' --filter "publish=8080" | head -n 1)

# Find the API container (linked to web or just running inv-api image)
API_CONTAINER_ID=$(docker ps --format '{{.ID}}' --filter "ancestor=inv-api:latest" | head -n 1)

# Find Redis
CACHE_CONTAINER_ID=$(docker ps --format '{{.ID}}' --filter "ancestor=redis:7-alpine" | head -n 1)

# Find Postgres
DB_CONTAINER_ID=$(docker ps --format '{{.ID}}' --filter "ancestor=postgres:14" | head -n 1)

# 4. Check if Original Containers are Stopped
ORIGINALS_STOPPED="true"
if docker ps --format '{{.Names}}' | grep -qE "^inv-db$|^inv-cache$|^inv-api$|^inv-web$"; then
    # If any of the original names are still running, check if they are the OLD IDs
    # (Agent might reuse names, which is fine, as long as they are recreated/restarted)
    # Actually, simpler: check if the IDs listed in /tmp/original_container_ids.txt are currently running
    while read -r old_id; do
        if docker ps --no-trunc -q | grep -q "$old_id"; then
            ORIGINALS_STOPPED="false"
        fi
    done < /tmp/original_container_ids.txt
fi

# 5. Extract Configurations from CURRENT Running Containers (The ones the agent launched)

# Config: DB Volume
DB_MOUNTS=""
[ -n "$DB_CONTAINER_ID" ] && DB_MOUNTS=$(docker inspect "$DB_CONTAINER_ID" --format '{{json .Mounts}}')

# Config: Redis Command
CACHE_CMD=""
[ -n "$CACHE_CONTAINER_ID" ] && CACHE_CMD=$(docker inspect "$CACHE_CONTAINER_ID" --format '{{json .Config.Cmd}}')

# Config: API Networks
API_NETWORKS=""
[ -n "$API_CONTAINER_ID" ] && API_NETWORKS=$(docker inspect "$API_CONTAINER_ID" --format '{{json .NetworkSettings.Networks}}')

# Config: API Env
API_ENV=""
[ -n "$API_CONTAINER_ID" ] && API_ENV=$(docker inspect "$API_CONTAINER_ID" --format '{{json .Config.Env}}')

# Config: Web Port
WEB_PORTS=""
[ -n "$WEB_CONTAINER_ID" ] && WEB_PORTS=$(docker inspect "$WEB_CONTAINER_ID" --format '{{json .NetworkSettings.Ports}}')


# 6. Compose Check (is it actually a compose project?)
IS_COMPOSE="false"
if [ -n "$WEB_CONTAINER_ID" ]; then
    LABELS=$(docker inspect "$WEB_CONTAINER_ID" --format '{{json .Config.Labels}}')
    if echo "$LABELS" | grep -q "com.docker.compose.project"; then
        IS_COMPOSE="true"
    fi
fi

# Create JSON Result
cat > /tmp/task_result.json <<EOF
{
    "compose_file_exists": $COMPOSE_EXISTS,
    "valid_yaml": $VALID_YAML,
    "api_items_status": $API_ITEMS_STATUS,
    "api_status_status": $API_STATUS_STATUS,
    "originals_stopped": $ORIGINALS_STOPPED,
    "is_compose_project": $IS_COMPOSE,
    "db_container_found": $([ -n "$DB_CONTAINER_ID" ] && echo "true" || echo "false"),
    "db_mounts_json": $(echo "$DB_MOUNTS" | jq -R .),
    "cache_container_found": $([ -n "$CACHE_CONTAINER_ID" ] && echo "true" || echo "false"),
    "cache_cmd_json": $(echo "$CACHE_CMD" | jq -R .),
    "api_container_found": $([ -n "$API_CONTAINER_ID" ] && echo "true" || echo "false"),
    "api_networks_json": $(echo "$API_NETWORKS" | jq -R .),
    "api_env_json": $(echo "$API_ENV" | jq -R .),
    "web_container_found": $([ -n "$WEB_CONTAINER_ID" ] && echo "true" || echo "false"),
    "web_ports_json": $(echo "$WEB_PORTS" | jq -R .)
}
EOF

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete."
cat /tmp/task_result.json