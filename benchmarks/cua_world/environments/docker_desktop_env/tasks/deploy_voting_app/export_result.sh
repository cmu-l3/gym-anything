#!/bin/bash
# Export script for deploy_voting_app task (post_task hook)
# Gathers verification data for the real Docker Voting App deployment

echo "=== Exporting deploy_voting_app task result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Get initial state
INITIAL_COUNT=$(cat /tmp/initial_container_count 2>/dev/null || echo "0")

# Get current container state
CURRENT_COUNT=$(docker ps --format '{{.Names}}' 2>/dev/null | wc -l)

# Check for voting app containers using docker-compose project inspection
# This is more reliable than name substring matching
VOTE_RUNNING="false"
RESULT_RUNNING="false"
WORKER_RUNNING="false"
REDIS_RUNNING="false"
DB_RUNNING="false"

# First try to detect services via docker-compose project (most reliable)
cd /home/ga/voting-app 2>/dev/null
COMPOSE_SERVICES=$(docker compose ps --format '{{.Service}}:{{.State}}' 2>/dev/null || echo "")

if [ -n "$COMPOSE_SERVICES" ]; then
    # Use docker-compose service detection (authoritative)
    echo "$COMPOSE_SERVICES" | grep -q "^vote:running" && VOTE_RUNNING="true"
    echo "$COMPOSE_SERVICES" | grep -q "^result:running" && RESULT_RUNNING="true"
    echo "$COMPOSE_SERVICES" | grep -q "^worker:running" && WORKER_RUNNING="true"
    echo "$COMPOSE_SERVICES" | grep -q "^redis:running" && REDIS_RUNNING="true"
    echo "$COMPOSE_SERVICES" | grep -q "^db:running" && DB_RUNNING="true"
else
    # Fallback: Check containers by image (more reliable than name matching)
    for container in $(docker ps --format '{{.Names}}:{{.Image}}' 2>/dev/null); do
        name=$(echo "$container" | cut -d: -f1)
        image=$(echo "$container" | cut -d: -f2-)
        case "$image" in
            *examplevotingapp_vote*) VOTE_RUNNING="true" ;;
            *examplevotingapp_result*) RESULT_RUNNING="true" ;;
            *examplevotingapp_worker*) WORKER_RUNNING="true" ;;
            redis:*) REDIS_RUNNING="true" ;;
            postgres:*) DB_RUNNING="true" ;;
        esac
    done
fi

# Count how many voting app services are running
VOTING_APP_SERVICES=0
[ "$VOTE_RUNNING" = "true" ] && VOTING_APP_SERVICES=$((VOTING_APP_SERVICES + 1))
[ "$RESULT_RUNNING" = "true" ] && VOTING_APP_SERVICES=$((VOTING_APP_SERVICES + 1))
[ "$WORKER_RUNNING" = "true" ] && VOTING_APP_SERVICES=$((VOTING_APP_SERVICES + 1))
[ "$REDIS_RUNNING" = "true" ] && VOTING_APP_SERVICES=$((VOTING_APP_SERVICES + 1))
[ "$DB_RUNNING" = "true" ] && VOTING_APP_SERVICES=$((VOTING_APP_SERVICES + 1))

# Check if web interfaces are accessible (with retry logic for slow startup)
VOTE_ACCESSIBLE="false"
RESULT_ACCESSIBLE="false"
VOTE_HTTP="000"
RESULT_HTTP="000"

# Retry vote UI check (port 5001) - up to 5 attempts with 2 second delay
for attempt in 1 2 3 4 5; do
    VOTE_HTTP=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 3 http://localhost:5001 2>/dev/null || echo "000")
    if [ "$VOTE_HTTP" = "200" ]; then
        VOTE_ACCESSIBLE="true"
        break
    fi
    sleep 2
done

# Retry result UI check (port 5002) - up to 5 attempts with 2 second delay
for attempt in 1 2 3 4 5; do
    RESULT_HTTP=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 3 http://localhost:5002 2>/dev/null || echo "000")
    if [ "$RESULT_HTTP" = "200" ]; then
        RESULT_ACCESSIBLE="true"
        break
    fi
    sleep 2
done

# Get list of all running containers
RUNNING_CONTAINERS=$(docker ps --format '{{.Names}}:{{.Image}}:{{.Status}}' 2>/dev/null | tr '\n' '|' | sed 's/|$//')

# Get container ports
CONTAINER_PORTS=$(docker ps --format '{{.Names}}:{{.Ports}}' 2>/dev/null | tr '\n' '|' | sed 's/|$//')

# Check if Docker Desktop is running
DOCKER_DESKTOP_RUNNING="false"
if pgrep -f "com.docker.backend" > /dev/null 2>&1 || \
   pgrep -f "/opt/docker-desktop/Docker" > /dev/null 2>&1; then
    DOCKER_DESKTOP_RUNNING="true"
fi

# Check if Docker daemon is working
DOCKER_DAEMON_READY="false"
if timeout 5 docker info > /dev/null 2>&1; then
    DOCKER_DAEMON_READY="true"
fi

# Check for docker-compose project health
COMPOSE_PROJECT_HEALTHY="false"
cd /home/ga/voting-app
if su - ga -c "cd /home/ga/voting-app && docker compose ps --format '{{.State}}'" 2>/dev/null | grep -q "running"; then
    COMPOSE_PROJECT_HEALTHY="true"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task": "deploy_voting_app",
    "initial_container_count": $INITIAL_COUNT,
    "current_container_count": $CURRENT_COUNT,
    "voting_app_services_running": $VOTING_APP_SERVICES,
    "services": {
        "vote": $VOTE_RUNNING,
        "result": $RESULT_RUNNING,
        "worker": $WORKER_RUNNING,
        "redis": $REDIS_RUNNING,
        "db": $DB_RUNNING
    },
    "web_interfaces": {
        "vote_accessible": $VOTE_ACCESSIBLE,
        "vote_http_code": "$VOTE_HTTP",
        "result_accessible": $RESULT_ACCESSIBLE,
        "result_http_code": "$RESULT_HTTP"
    },
    "running_containers": "$RUNNING_CONTAINERS",
    "container_ports": "$CONTAINER_PORTS",
    "compose_project_healthy": $COMPOSE_PROJECT_HEALTHY,
    "docker_desktop_running": $DOCKER_DESKTOP_RUNNING,
    "docker_daemon_ready": $DOCKER_DAEMON_READY,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location with fallbacks
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="
