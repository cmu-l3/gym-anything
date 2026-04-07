#!/bin/bash
echo "=== Exporting local_registry_image_workflow Result ==="

source /workspace/scripts/task_utils.sh

if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

take_screenshot /tmp/task_end_screenshot.png

APP_DIR="/home/ga/api-service"

# --- Check 1: Registry running on port 5000 ---
REGISTRY_RUNNING="false"
REGISTRY_ACCESSIBLE="false"

if docker ps --format "{{.Image}}" 2>/dev/null | grep -q "registry:2\|registry"; then
    REGISTRY_RUNNING="true"
fi

# Test registry API
REGISTRY_PING=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 10 http://localhost:5000/v2/ 2>/dev/null || echo "000")
if [ "$REGISTRY_PING" = "200" ] || [ "$REGISTRY_PING" = "401" ]; then
    REGISTRY_ACCESSIBLE="true"
fi

# --- Check 2 & 3: Image tags in registry ---
HAS_V100_TAG="false"
HAS_LATEST_TAG="false"
REGISTRY_CATALOG=""

if [ "$REGISTRY_ACCESSIBLE" = "true" ]; then
    # Get catalog
    REGISTRY_CATALOG=$(curl -s --connect-timeout 5 --max-time 10 http://localhost:5000/v2/_catalog 2>/dev/null || echo "{}")

    # Get tags for api-service
    TAGS_RESPONSE=$(curl -s --connect-timeout 5 --max-time 10 http://localhost:5000/v2/api-service/tags/list 2>/dev/null || echo "{}")

    if echo "$TAGS_RESPONSE" | grep -q '"v1.0.0"'; then
        HAS_V100_TAG="true"
    fi
    if echo "$TAGS_RESPONSE" | grep -q '"latest"'; then
        HAS_LATEST_TAG="true"
    fi
fi

# Escape for JSON
CATALOG_ESCAPED=$(echo "$REGISTRY_CATALOG" | tr -d '\n' | sed 's/"/\\"/g')

# --- Check 4: Compose uses registry image (not build:) ---
COMPOSE_USES_REGISTRY="false"
COMPOSE_HAS_BUILD="false"

COMPOSE_FILE="$APP_DIR/docker-compose.yml"
if [ -f "$COMPOSE_FILE" ]; then
    if grep -qE "image:\s*localhost:5000/api-service" "$COMPOSE_FILE"; then
        COMPOSE_USES_REGISTRY="true"
    fi
    if grep -qE "^\s*build:" "$COMPOSE_FILE"; then
        COMPOSE_HAS_BUILD="true"
    fi
fi

# --- Check 5: API accessible on port 7080 ---
API_HTTP_CODE="000"
for i in 1 2 3 4 5; do
    CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 10 http://localhost:7080 2>/dev/null || echo "000")
    if [ "$CODE" = "200" ]; then
        API_HTTP_CODE="$CODE"
        break
    fi
    # Also check /health
    CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 10 http://localhost:7080/health 2>/dev/null || echo "000")
    if [ "$CODE" = "200" ]; then
        API_HTTP_CODE="$CODE"
        break
    fi
    sleep 2
done

cat > /tmp/local_registry_image_workflow_result.json << JSONEOF
{
    "registry_running": $REGISTRY_RUNNING,
    "registry_accessible": $REGISTRY_ACCESSIBLE,
    "registry_ping_code": "$REGISTRY_PING",
    "has_v100_tag": $HAS_V100_TAG,
    "has_latest_tag": $HAS_LATEST_TAG,
    "compose_uses_registry": $COMPOSE_USES_REGISTRY,
    "compose_has_build": $COMPOSE_HAS_BUILD,
    "api_http_code": "$API_HTTP_CODE",
    "export_timestamp": "$(date -Iseconds)"
}
JSONEOF

echo "=== Export Complete ==="
cat /tmp/local_registry_image_workflow_result.json
