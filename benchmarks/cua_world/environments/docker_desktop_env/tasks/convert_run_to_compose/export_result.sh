#!/bin/bash
# Export script for convert_run_to_compose task

echo "=== Exporting convert_run_to_compose result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/monitoring-stack"
COMPOSE_FILE="$PROJECT_DIR/docker-compose.yml"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check Compose File
COMPOSE_EXISTS="false"
COMPOSE_VALID="false"
COMPOSE_CONTENT=""
if [ -f "$COMPOSE_FILE" ]; then
    COMPOSE_EXISTS="true"
    COMPOSE_CONTENT=$(cat "$COMPOSE_FILE" | base64 -w 0)
    # Validate with docker compose config
    if cd "$PROJECT_DIR" && docker compose config > /dev/null 2>&1; then
        COMPOSE_VALID="true"
    fi
fi

# 2. Check Services Running (via Docker Compose)
cd "$PROJECT_DIR" 2>/dev/null
RUNNING_SERVICES=$(docker compose ps --services --filter "status=running" 2>/dev/null | tr '\n' ',' | sed 's/,$//')

# 3. Check HTTP Endpoints
check_http() {
    local url="$1"
    local expected="$2"
    curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 "$url" || echo "000"
}

PROM_HTTP=$(check_http "http://localhost:9090/-/ready" "200")
GRAFANA_HTTP=$(check_http "http://localhost:3000/api/health" "200")
NODE_HTTP=$(check_http "http://localhost:9100/metrics" "200")

# 4. Check Prometheus Target Status (is it scraping node-exporter?)
PROM_TARGETS_UP="false"
if [ "$PROM_HTTP" = "200" ]; then
    # Query API for targets
    TARGETS_JSON=$(curl -s "http://localhost:9090/api/v1/targets")
    if echo "$TARGETS_JSON" | grep -q '"health":"up"'; then
        # Check specifically for node-exporter
        if echo "$TARGETS_JSON" | grep -q "node-exporter"; then
            PROM_TARGETS_UP="true"
        fi
    fi
fi

# 5. Inspect Containers for Configuration Accuracy
# We need to verify that they translated the flags correctly (ports, volumes, envs, restart)

inspect_container() {
    local service="$1"
    # Get container ID for the service
    local cid=$(docker compose ps -q "$service" 2>/dev/null)
    
    if [ -z "$cid" ]; then
        echo "{}"
        return
    fi
    
    # Inspect and return minimal JSON
    docker inspect "$cid" --format '{{json .}}'
}

PROM_INSPECT=$(inspect_container "prometheus")
GRAF_INSPECT=$(inspect_container "grafana")
NODE_INSPECT=$(inspect_container "node-exporter")

# 6. Check Volumes
VOLUMES=$(docker volume ls --format '{{.Name}}' | tr '\n' ',' | sed 's/,$//')

# 7. Check if run_commands.sh was executed (anti-gaming)
# If the containers are NOT part of a compose project, specific labels will be missing
COMPOSE_PROJECT_LABEL="com.docker.compose.project"

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "compose_exists": $COMPOSE_EXISTS,
    "compose_valid": $COMPOSE_VALID,
    "compose_content_b64": "$COMPOSE_CONTENT",
    "running_services": "$RUNNING_SERVICES",
    "http_endpoints": {
        "prometheus": "$PROM_HTTP",
        "grafana": "$GRAFANA_HTTP",
        "node_exporter": "$NODE_HTTP"
    },
    "prometheus_targets_up": $PROM_TARGETS_UP,
    "container_configs": {
        "prometheus": $PROM_INSPECT,
        "grafana": $GRAF_INSPECT,
        "node_exporter": $NODE_INSPECT
    },
    "volumes_list": "$VOLUMES",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="