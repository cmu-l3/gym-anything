#!/bin/bash
# Export script for docker_runtime_config task

echo "=== Exporting Results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true
take_screenshot /tmp/task_final.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
IMAGE_TAG="acme-dashboard:dynamic"

# Initialize Result Variables
IMAGE_EXISTS="false"
CONTAINER_STARTED="false"
CONFIG_JS_INJECTED="false"
NGINX_CONF_INJECTED="false"
NGINX_VARS_PRESERVED="false"
NGINX_RUNNING="false"
DOCKERFILE_HAS_GETTEXT="false"
ENTRYPOINT_EXISTS="false"

# 1. Check if image exists
if docker inspect "$IMAGE_TAG" >/dev/null 2>&1; then
    IMAGE_EXISTS="true"
    echo "Image $IMAGE_TAG found."
else
    echo "Image $IMAGE_TAG NOT found."
fi

# 2. Run Verification Container
if [ "$IMAGE_EXISTS" = "true" ]; then
    # Generate random test values to prevent hardcoding
    TEST_API_URL="https://api-verify-$(date +%s).example.com"
    TEST_WORKERS="7" # Unusual number to verify injection
    
    echo "Starting verification container with:"
    echo "  API_URL=$TEST_API_URL"
    echo "  WORKER_PROCESSES=$TEST_WORKERS"

    # Cleanup any stale verification container
    docker rm -f verify-run 2>/dev/null || true

    # Run detached
    docker run -d --name verify-run \
        -e API_URL="$TEST_API_URL" \
        -e WORKER_PROCESSES="$TEST_WORKERS" \
        "$IMAGE_TAG"
    
    # Wait for startup
    sleep 5

    # Check if container is still running
    if [ "$(docker inspect -f '{{.State.Running}}' verify-run 2>/dev/null)" = "true" ]; then
        CONTAINER_STARTED="true"
        
        # Check Nginx process
        if docker exec verify-run pgrep nginx >/dev/null 2>&1; then
            NGINX_RUNNING="true"
        fi

        # Check config.js injection
        ACTUAL_CONFIG_JS=$(docker exec verify-run cat /usr/share/nginx/html/config.js 2>/dev/null)
        if echo "$ACTUAL_CONFIG_JS" | grep -q "$TEST_API_URL"; then
            CONFIG_JS_INJECTED="true"
        fi

        # Check nginx.conf injection
        ACTUAL_NGINX_CONF=$(docker exec verify-run cat /etc/nginx/nginx.conf 2>/dev/null)
        if echo "$ACTUAL_NGINX_CONF" | grep -q "worker_processes $TEST_WORKERS;"; then
            NGINX_CONF_INJECTED="true"
        fi

        # Check Nginx internal variables preservation
        # If envsubst destroyed them, '$uri' would be empty or missing
        # We search for the literal string '$uri' and '$host'
        HAS_URI=0
        HAS_HOST=0
        echo "$ACTUAL_NGINX_CONF" | grep -Fq '$uri' && HAS_URI=1
        echo "$ACTUAL_NGINX_CONF" | grep -Fq '$host' && HAS_HOST=1
        
        if [ "$HAS_URI" -eq 1 ] && [ "$HAS_HOST" -eq 1 ]; then
            NGINX_VARS_PRESERVED="true"
        fi
        
    else
        echo "Container verify-run failed to start/stay running."
        echo "Logs:"
        docker logs verify-run | tail -n 20
    fi
fi

# 3. Static Analysis
PROJECT_DIR="/home/ga/projects/acme-dashboard"
if [ -f "$PROJECT_DIR/Dockerfile" ]; then
    # Check for gettext installation
    if grep -E "apk.*add.*gettext" "$PROJECT_DIR/Dockerfile"; then
        DOCKERFILE_HAS_GETTEXT="true"
    fi
fi

if [ -f "$PROJECT_DIR/docker-entrypoint.sh" ] || ls "$PROJECT_DIR" | grep -q "entrypoint"; then
    ENTRYPOINT_EXISTS="true"
fi

# 4. Generate Result JSON
cat > /tmp/task_result.json <<EOF
{
    "task_start": $TASK_START,
    "image_exists": $IMAGE_EXISTS,
    "container_started": $CONTAINER_STARTED,
    "nginx_running": $NGINX_RUNNING,
    "config_js_injected": $CONFIG_JS_INJECTED,
    "nginx_conf_injected": $NGINX_CONF_INJECTED,
    "nginx_vars_preserved": $NGINX_VARS_PRESERVED,
    "dockerfile_has_gettext": $DOCKERFILE_HAS_GETTEXT,
    "entrypoint_exists": $ENTRYPOINT_EXISTS,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="