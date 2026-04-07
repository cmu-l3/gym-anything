#!/bin/bash
echo "=== Exporting Scaling Task Result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/scaling-app"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Verification File Check
VERIFICATION_FILE="$PROJECT_DIR/verification.txt"
VERIFICATION_FILE_EXISTS="false"
VERIFICATION_CONTENT=""
if [ -f "$VERIFICATION_FILE" ]; then
    VERIFICATION_FILE_EXISTS="true"
    VERIFICATION_CONTENT=$(head -n 20 "$VERIFICATION_FILE")
fi

# 2. Independent Load Balancing Test (The "Truth" Test)
# We make 20 requests and verify we see multiple hostnames
LB_TEST_PASSED="false"
UNIQUE_HOSTS_COUNT=0
LB_RESPONSES=""

if curl -s http://localhost:8080 > /dev/null; then
    # Capture 20 requests
    LB_RESPONSES=$(for i in {1..20}; do curl -s http://localhost:8080; echo ""; done)
    
    # Extract "Hello from [hostname]!" and count unique hostnames
    UNIQUE_HOSTS_COUNT=$(echo "$LB_RESPONSES" | grep "Hello from" | sed 's/Hello from \([^!]*\).*/\1/' | sort | uniq | wc -l)
    
    if [ "$UNIQUE_HOSTS_COUNT" -ge 2 ]; then
        LB_TEST_PASSED="true"
    fi
fi

# 3. Redis Counter Check
# If Redis is working, the "Visit count" should be increasing or at least > 1
REDIS_WORKING="false"
LAST_COUNT=$(echo "$LB_RESPONSES" | grep "Visit count" | tail -1 | awk -F': ' '{print $2}')
if [[ "$LAST_COUNT" =~ ^[0-9]+$ ]] && [ "$LAST_COUNT" -gt 0 ]; then
    REDIS_WORKING="true"
fi

# 4. Container State Check
# Parse docker compose ps to see what's actually running
cd "$PROJECT_DIR" || exit 1
COMPOSE_PS_JSON=$(docker compose ps --format json 2>/dev/null)
RUNNING_CONTAINERS=$(docker compose ps --format "{{.Service}}:{{.State}}" 2>/dev/null)

FLASK_COUNT=$(echo "$RUNNING_CONTAINERS" | grep "flask" | grep "running" | wc -l)
NGINX_RUNNING=$(echo "$RUNNING_CONTAINERS" | grep "nginx:running" | wc -l)
REDIS_RUNNING=$(echo "$RUNNING_CONTAINERS" | grep "redis:running" | wc -l)

# 5. Configuration File Analysis
COMPOSE_CONTENT=$(cat docker-compose.yml 2>/dev/null)
NGINX_CONF_CONTENT=$(cat nginx/default.conf 2>/dev/null)

# Check for replicas: 3
HAS_REPLICAS="false"
if echo "$COMPOSE_CONTENT" | grep -q "replicas:.*3"; then
    HAS_REPLICAS="true"
fi

# Check for removal of container_name in flask service
HAS_CONTAINER_NAME_CONFLICT="false"
# Simple heuristic: if we see 'container_name' inside the flask block
# Python verifier can do a better job parsing YAML, but let's do a basic check here
# We'll rely on the Python verifier to parse the YAML content string.

# Check for nginx resolver or upstream
NGINX_HAS_RESOLVER="false"
if echo "$NGINX_CONF_CONTENT" | grep -q "resolver.*127.0.0.11" || echo "$NGINX_CONF_CONTENT" | grep -q "upstream"; then
    NGINX_HAS_RESOLVER="true"
fi

# 6. File Timestamps (Anti-Gaming)
COMPOSE_MODIFIED="false"
NGINX_MODIFIED="false"

COMPOSE_MTIME=$(stat -c %Y docker-compose.yml 2>/dev/null || echo "0")
NGINX_MTIME=$(stat -c %Y nginx/default.conf 2>/dev/null || echo "0")

if [ "$COMPOSE_MTIME" -gt "$TASK_START" ]; then COMPOSE_MODIFIED="true"; fi
if [ "$NGINX_MTIME" -gt "$TASK_START" ]; then NGINX_MODIFIED="true"; fi

# Take Final Screenshot
take_screenshot /tmp/task_final.png

# Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "verification_file_exists": $VERIFICATION_FILE_EXISTS,
    "verification_file_content": $(echo "$VERIFICATION_CONTENT" | jq -R -s '.'),
    "lb_test_passed": $LB_TEST_PASSED,
    "unique_hosts_observed": $UNIQUE_HOSTS_COUNT,
    "redis_working": $REDIS_WORKING,
    "flask_containers_running": $FLASK_COUNT,
    "nginx_running": $NGINX_RUNNING,
    "redis_running": $REDIS_RUNNING,
    "compose_file_content": $(echo "$COMPOSE_CONTENT" | jq -R -s '.'),
    "nginx_conf_content": $(echo "$NGINX_CONF_CONTENT" | jq -R -s '.'),
    "compose_modified": $COMPOSE_MODIFIED,
    "nginx_modified": $NGINX_MODIFIED,
    "nginx_has_resolver_heuristic": $NGINX_HAS_RESOLVER,
    "has_replicas_heuristic": $HAS_REPLICAS
}
EOF

# Save result with permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="