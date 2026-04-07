#!/bin/bash
# Export script for docker_compose_external_bridge task

echo "=== Exporting Results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INIT_MTIME_INFRA=$(cat /tmp/initial_mtime_infra.txt 2>/dev/null || echo "0")
INIT_MTIME_API=$(cat /tmp/initial_mtime_api.txt 2>/dev/null || echo "0")

# 1. Check Network Existence
NET_DB_EXISTS=$(docker network ls --format '{{.Name}}' | grep -qx "infra-db-net" && echo "true" || echo "false")
NET_CACHE_EXISTS=$(docker network ls --format '{{.Name}}' | grep -qx "infra-cache-net" && echo "true" || echo "false")

# 2. Check Container State
# We expect 3 specific containers to be running
CTR_POSTGRES_RUNNING=$(docker ps --filter "name=shared-postgres" --format '{{.State}}' | grep -q "running" && echo "true" || echo "false")
CTR_REDIS_RUNNING=$(docker ps --filter "name=shared-redis" --format '{{.State}}' | grep -q "running" && echo "true" || echo "false")
CTR_API_RUNNING=$(docker ps --filter "name=flask-api" --format '{{.State}}' | grep -q "running" && echo "true" || echo "false")

# 3. Check Network Membership (The core of the task)
# Does shared-postgres belong to infra-db-net?
POSTGRES_NETS=$(docker inspect shared-postgres --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}' 2>/dev/null)
POSTGRES_ON_DB_NET=$(echo "$POSTGRES_NETS" | grep -q "infra-db-net" && echo "true" || echo "false")

# Does shared-redis belong to infra-cache-net?
REDIS_NETS=$(docker inspect shared-redis --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}' 2>/dev/null)
REDIS_ON_CACHE_NET=$(echo "$REDIS_NETS" | grep -q "infra-cache-net" && echo "true" || echo "false")

# Does flask-api belong to BOTH?
API_NETS=$(docker inspect flask-api --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}' 2>/dev/null)
API_ON_DB_NET=$(echo "$API_NETS" | grep -q "infra-db-net" && echo "true" || echo "false")
API_ON_CACHE_NET=$(echo "$API_NETS" | grep -q "infra-cache-net" && echo "true" || echo "false")

# 4. Functional Health Checks (The "Proof")
# We hit the Flask API which tries to connect to the backend services
API_HEALTH_DB_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 http://localhost:5050/health/db || echo "000")
API_HEALTH_REDIS_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 http://localhost:5050/health/redis || echo "000")

# 5. Check File Modification (Anti-Gaming)
CUR_MTIME_INFRA=$(stat -c %Y /home/ga/Documents/docker-projects/shared-infra/docker-compose.yml 2>/dev/null || echo "0")
CUR_MTIME_API=$(stat -c %Y /home/ga/Documents/docker-projects/flask-api/docker-compose.yml 2>/dev/null || echo "0")

MODIFIED_INFRA="false"
if [ "$CUR_MTIME_INFRA" -gt "$INIT_MTIME_INFRA" ]; then MODIFIED_INFRA="true"; fi

MODIFIED_API="false"
if [ "$CUR_MTIME_API" -gt "$INIT_MTIME_API" ]; then MODIFIED_API="true"; fi

# 6. Check Connectivity Report
REPORT_PATH="/home/ga/Documents/docker-projects/connectivity-report.txt"
REPORT_EXISTS="false"
REPORT_CONTENT=""
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    # Read first 500 chars to avoid huge output
    REPORT_CONTENT=$(head -c 500 "$REPORT_PATH")
fi

# 7. Take Final Screenshot
take_screenshot /tmp/task_end.png

# 8. Compile JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "networks": {
        "infra-db-net": $NET_DB_EXISTS,
        "infra-cache-net": $NET_CACHE_EXISTS
    },
    "containers_running": {
        "postgres": $CTR_POSTGRES_RUNNING,
        "redis": $CTR_REDIS_RUNNING,
        "api": $CTR_API_RUNNING
    },
    "network_membership": {
        "postgres_on_db_net": $POSTGRES_ON_DB_NET,
        "redis_on_cache_net": $REDIS_ON_CACHE_NET,
        "api_on_db_net": $API_ON_DB_NET,
        "api_on_cache_net": $API_ON_CACHE_NET
    },
    "health_checks": {
        "db_http_code": "$API_HEALTH_DB_CODE",
        "redis_http_code": "$API_HEALTH_REDIS_CODE"
    },
    "files_modified": {
        "infra_compose": $MODIFIED_INFRA,
        "api_compose": $MODIFIED_API
    },
    "report": {
        "exists": $REPORT_EXISTS,
        "content_preview": "$(json_escape "$REPORT_CONTENT")"
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="