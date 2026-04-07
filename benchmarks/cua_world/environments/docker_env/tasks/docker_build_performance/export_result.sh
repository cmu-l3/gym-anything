#!/bin/bash
# Export script for docker_build_performance task

echo "=== Exporting Docker Build Performance Results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true
take_screenshot /tmp/task_end_screenshot.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
INITIAL_SIZE_MB=$(cat /tmp/initial_image_size_mb 2>/dev/null || echo "1200")
PROJECT_DIR="/home/ga/projects/analytics-service"

# ── Detect if AGENT replaced :optimized (check before export rebuilds it) ────
# Compare current image ID against the baseline ID saved during setup
INITIAL_IMAGE_ID=$(cat /tmp/initial_optimized_image_id 2>/dev/null | tr -d '[:space:]' || echo "")
CURRENT_IMAGE_ID=$(docker inspect acme-analytics:optimized --format '{{.Id}}' 2>/dev/null | tr -d '[:space:]' || echo "")
AGENT_REBUILT=0
if [ -n "$CURRENT_IMAGE_ID" ] && [ -n "$INITIAL_IMAGE_ID" ] && [ "$CURRENT_IMAGE_ID" != "$INITIAL_IMAGE_ID" ]; then
    AGENT_REBUILT=1
fi
echo "Agent rebuilt :optimized: $AGENT_REBUILT (initial_id=${INITIAL_IMAGE_ID:0:12} current_id=${CURRENT_IMAGE_ID:0:12})"

# ── Image size check (before export rebuild) ──────────────────────────────────
OPTIMIZED_SIZE_BYTES=$(docker inspect acme-analytics:optimized --format '{{.Size}}' 2>/dev/null || echo "0")
OPTIMIZED_SIZE_MB=$(echo "$OPTIMIZED_SIZE_BYTES" | awk '{printf "%.0f", $1/1048576}' 2>/dev/null || echo "9999")

# ── Cached build time measurement ─────────────────────────────────────────────
# Make a trivial code change to force app layer rebuild (not deps layer)
echo "Measuring cached build time (touching app code, deps should cache)..."
echo "# cache test comment $(date +%s)" >> "$PROJECT_DIR/app/main.py" 2>/dev/null || true

CACHED_BUILD_SEC=9999
if [ -f "$PROJECT_DIR/Dockerfile" ]; then
    BUILD_START=$(date +%s)
    export DOCKER_BUILDKIT=1
    docker build -t acme-analytics:optimized "$PROJECT_DIR/" -q > /tmp/cached_build.log 2>&1 || true
    BUILD_END=$(date +%s)
    CACHED_BUILD_SEC=$((BUILD_END - BUILD_START))
    echo "Cached build time: ${CACHED_BUILD_SEC}s"
fi

# ── .dockerignore check ───────────────────────────────────────────────────────
DOCKERIGNORE_EXISTS=0
DOCKERIGNORE_SIZE=0
[ -f "$PROJECT_DIR/.dockerignore" ] && DOCKERIGNORE_EXISTS=1
[ "$DOCKERIGNORE_EXISTS" = "1" ] && DOCKERIGNORE_SIZE=$(wc -l < "$PROJECT_DIR/.dockerignore" 2>/dev/null || echo "0")

# ── Dev dependencies check ───────────────────────────────────────────────────
# Check if dev packages like pytest, black, locust are in the optimized image
DEV_DEPS_EXCLUDED=1
PYTEST_IN_IMAGE=0
docker run --rm --entrypoint="" acme-analytics:optimized pip show pytest 2>/dev/null | grep -q "Name: pytest" && PYTEST_IN_IMAGE=1
BLACK_IN_IMAGE=0
docker run --rm --entrypoint="" acme-analytics:optimized pip show black 2>/dev/null | grep -q "Name: black" && BLACK_IN_IMAGE=1
# If either dev dep is present, dev deps not properly excluded
if [ "$PYTEST_IN_IMAGE" = "1" ] || [ "$BLACK_IN_IMAGE" = "1" ]; then
    DEV_DEPS_EXCLUDED=0
fi

# ── Application health check ──────────────────────────────────────────────────
APP_RESPONDS=0
APP_STATUS_CODE="000"

# Start the optimized container
docker rm -f acme-analytics-test 2>/dev/null || true
docker run -d --name acme-analytics-test -p 8001:8000 acme-analytics:optimized 2>/dev/null || true
sleep 8

APP_STATUS_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8001/health 2>/dev/null || echo "000")
[ "$APP_STATUS_CODE" = "200" ] && APP_RESPONDS=1

docker rm -f acme-analytics-test 2>/dev/null || true

cat > /tmp/docker_build_result.json << JSONEOF
{
    "task_start": $TASK_START,
    "initial_size_mb": $INITIAL_SIZE_MB,
    "optimized_size_mb": $OPTIMIZED_SIZE_MB,
    "agent_rebuilt": $AGENT_REBUILT,
    "cached_build_sec": $CACHED_BUILD_SEC,
    "dockerignore_exists": $DOCKERIGNORE_EXISTS,
    "dockerignore_lines": $DOCKERIGNORE_SIZE,
    "dev_deps_excluded": $DEV_DEPS_EXCLUDED,
    "pytest_in_image": $PYTEST_IN_IMAGE,
    "app_responds": $APP_RESPONDS,
    "app_status_code": "$APP_STATUS_CODE",
    "export_timestamp": "$(date -Iseconds)"
}
JSONEOF

echo "Build performance results:"
cat /tmp/docker_build_result.json
echo "=== Export Complete ==="
