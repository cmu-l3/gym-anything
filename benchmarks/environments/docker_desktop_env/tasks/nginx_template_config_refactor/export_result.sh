#!/bin/bash
echo "=== Exporting Nginx Template Refactor Result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/proxy-refactor"
TEST_INJECTION_VALUE="http://verification-test:9999"

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Static Analysis: Check file existence and content
# ---------------------------------------------------
COMPOSE_FILE="$PROJECT_DIR/docker-compose.yml"
NGINX_DIR="$PROJECT_DIR/nginx"

# Find if any template file exists
TEMPLATE_FILE=$(find "$NGINX_DIR" -name "*.template" | head -n 1)
TEMPLATE_EXISTS="false"
TEMPLATE_CONTENT=""
if [ -n "$TEMPLATE_FILE" ]; then
    TEMPLATE_EXISTS="true"
    TEMPLATE_CONTENT=$(cat "$TEMPLATE_FILE")
fi

# Check default.conf if template not found (maybe they just kept the name but mounted it to /templates)
DEFAULT_CONF_CONTENT=""
if [ -f "$NGINX_DIR/default.conf" ]; then
    DEFAULT_CONF_CONTENT=$(cat "$NGINX_DIR/default.conf")
fi

# Check docker-compose.yml content
COMPOSE_CONTENT=""
if [ -f "$COMPOSE_FILE" ]; then
    COMPOSE_CONTENT=$(cat "$COMPOSE_FILE")
fi

# 2. Functional Check: Does it work as configured by the agent?
# ------------------------------------------------------------
echo "Checking agent's current configuration..."
# Ensure it's running
cd "$PROJECT_DIR"
docker compose up -d --wait 2>/dev/null || true
sleep 2

FUNCTIONAL_CHECK="false"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 http://localhost 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
    # Double check content to ensure it's from whoami
    RESPONSE=$(curl -s --connect-timeout 2 http://localhost)
    if echo "$RESPONSE" | grep -q "Hostname"; then
        FUNCTIONAL_CHECK="true"
    fi
fi

# 3. Dynamic Verification: Inject random value
# --------------------------------------------
echo "Running dynamic injection test..."
DYNAMIC_CHECK="false"
GENERATED_CONFIG=""

# Stop the proxy
docker compose stop proxy 2>/dev/null || true
docker rm refactor-proxy 2>/dev/null || true

# Start proxy with INJECTED environment variable
# We use docker run manually or docker compose with env override
# Using compose is safer to keep mounts consistent
BACKEND_URL="$TEST_INJECTION_VALUE" docker compose up -d --force-recreate proxy 2>/dev/null || true

# Wait for template processing
sleep 3

# Check if the container is running
if [ "$(docker inspect -f '{{.State.Running}}' refactor-proxy 2>/dev/null)" = "true" ]; then
    # Read the generated config file from inside the container
    GENERATED_CONFIG=$(docker exec refactor-proxy cat /etc/nginx/conf.d/default.conf 2>/dev/null || echo "")
    
    # Check if our test value appears in the generated config
    if echo "$GENERATED_CONFIG" | grep -q "$TEST_INJECTION_VALUE"; then
        DYNAMIC_CHECK="true"
    fi
else
    echo "Proxy container failed to start during dynamic test"
fi

# Restore original state (politeness)
docker compose down 2>/dev/null || true

# 4. Create Result JSON
# ---------------------
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "template_exists": $TEMPLATE_EXISTS,
    "template_file_path": "$TEMPLATE_FILE",
    "template_content_snippet": $(json_escape "${TEMPLATE_CONTENT:0:500}"),
    "default_conf_snippet": $(json_escape "${DEFAULT_CONF_CONTENT:0:500}"),
    "compose_content_snippet": $(json_escape "${COMPOSE_CONTENT:0:1000}"),
    "functional_check_passed": $FUNCTIONAL_CHECK,
    "dynamic_check_passed": $DYNAMIC_CHECK,
    "generated_config_snippet": $(json_escape "${GENERATED_CONFIG:0:500}"),
    "test_injection_value": "$TEST_INJECTION_VALUE",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="