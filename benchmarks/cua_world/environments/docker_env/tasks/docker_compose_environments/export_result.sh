#!/bin/bash
# Export script for docker_compose_environments task

echo "=== Exporting Results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true
take_screenshot /tmp/task_final.png 2>/dev/null || true

PROJECT_DIR="/home/ga/projects/acme-analytics"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Verify File Existence & Content
FILE_BASE_EXISTS=0
FILE_DEV_EXISTS=0
FILE_PROD_EXISTS=0
CONTENT_BASE=""
CONTENT_DEV=""
CONTENT_PROD=""

if [ -f "$PROJECT_DIR/docker-compose.yml" ]; then
    FILE_BASE_EXISTS=1
    CONTENT_BASE=$(cat "$PROJECT_DIR/docker-compose.yml" | base64 -w 0)
fi
if [ -f "$PROJECT_DIR/docker-compose.override.yml" ]; then
    FILE_DEV_EXISTS=1
    CONTENT_DEV=$(cat "$PROJECT_DIR/docker-compose.override.yml" | base64 -w 0)
fi
if [ -f "$PROJECT_DIR/docker-compose.prod.yml" ]; then
    FILE_PROD_EXISTS=1
    CONTENT_PROD=$(cat "$PROJECT_DIR/docker-compose.prod.yml" | base64 -w 0)
fi

# 2. Inspect Running Containers (Production Verification)
# We expect containers named roughly like 'acme-analytics-api-1' or similar, depending on folder name.
# Using 'docker ps' filter by label is safer if they use 'compose', but name grep is robust enough for this environment.

# Get IDs of running containers related to the project
API_ID=$(docker ps -q --filter "ancestor=acme-analytics-api:latest" | head -1)
DB_ID=$(docker ps -q --filter "ancestor=postgres:14" | head -1)
CACHE_ID=$(docker ps -q --filter "ancestor=redis:7-alpine" | head -1)
NGINX_ID=$(docker ps -q --filter "ancestor=acme-analytics-nginx:latest" | head -1)
# Fallback for Nginx if they used 'nginx' image directly in compose
if [ -z "$NGINX_ID" ]; then
    NGINX_ID=$(docker ps -q --filter "ancestor=nginx:1.24-alpine" | head -1)
fi

inspect_container() {
    local id="$1"
    if [ -z "$id" ]; then echo "null"; return; fi
    docker inspect "$id" 2>/dev/null || echo "null"
}

API_INSPECT=$(inspect_container "$API_ID")
DB_INSPECT=$(inspect_container "$DB_ID")
CACHE_INSPECT=$(inspect_container "$CACHE_ID")
NGINX_INSPECT=$(inspect_container "$NGINX_ID")

# 3. Functional Test
API_RESPONSE_CODE="000"
API_RESPONSE_BODY=""
if [ -n "$NGINX_ID" ]; then
    # Try localhost:80 (prod) first, then 8080 (dev default) if 80 fails, to be generous
    API_RESPONSE_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:80/api/health 2>/dev/null || echo "000")
    if [ "$API_RESPONSE_CODE" = "000" ]; then
         API_RESPONSE_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/api/health 2>/dev/null || echo "000")
    fi
    
    # Capture body if successful
    if [ "$API_RESPONSE_CODE" = "200" ]; then
        API_RESPONSE_BODY=$(curl -s http://localhost:80/api/health 2>/dev/null || curl -s http://localhost:8080/api/health 2>/dev/null)
    fi
fi

# 4. JSON Export
cat > /tmp/task_result.json << EOF
{
    "task_start_time": $TASK_START,
    "files": {
        "base_exists": $FILE_BASE_EXISTS,
        "dev_exists": $FILE_DEV_EXISTS,
        "prod_exists": $FILE_PROD_EXISTS,
        "base_content_b64": "$CONTENT_BASE",
        "dev_content_b64": "$CONTENT_DEV",
        "prod_content_b64": "$CONTENT_PROD"
    },
    "containers": {
        "api": $API_INSPECT,
        "db": $DB_INSPECT,
        "cache": $CACHE_INSPECT,
        "nginx": $NGINX_INSPECT
    },
    "functional": {
        "response_code": "$API_RESPONSE_CODE",
        "response_body": "$API_RESPONSE_BODY"
    },
    "export_timestamp": $(date +%s)
}
EOF

# Handle file permissions
chmod 666 /tmp/task_result.json

echo "Export completed. Result size: $(wc -c < /tmp/task_result.json) bytes"