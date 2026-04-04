#!/bin/bash
echo "=== Exporting compose_production_hardening Result ==="

source /workspace/scripts/task_utils.sh

if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

take_screenshot /tmp/task_end_screenshot.png

APP_DIR="/home/ga/webapp"
COMPOSE_FILE="$APP_DIR/docker-compose.yml"

cd "$APP_DIR" 2>/dev/null

# --- Check compose file was modified ---
COMPOSE_MTIME=$(stat -c %Y "$COMPOSE_FILE" 2>/dev/null || echo "0")
INITIAL_MTIME=$(cat /tmp/initial_compose_mtime 2>/dev/null || echo "0")
COMPOSE_MODIFIED="false"
if [ "$COMPOSE_MTIME" -gt "$INITIAL_MTIME" ]; then
    COMPOSE_MODIFIED="true"
fi

# --- Get service container IDs ---
NGINX_CID=$(docker compose ps -q nginx 2>/dev/null | head -1)
APP_CID=$(docker compose ps -q app 2>/dev/null | head -1)
REDIS_CID=$(docker compose ps -q redis 2>/dev/null | head -1)

# --- Helper: check healthcheck via docker inspect ---
check_healthcheck() {
    local cid="$1"
    [ -z "$cid" ] && echo "false" && return
    local hc
    hc=$(docker inspect "$cid" --format '{{json .Config.Healthcheck}}' 2>/dev/null || echo "null")
    if [ -n "$hc" ] && [ "$hc" != "null" ] && [ "$hc" != "{}" ] && [ "$hc" != "<nil>" ]; then
        echo "true"
    else
        echo "false"
    fi
}

# --- Helper: check memory limit via docker inspect ---
check_memory_limit() {
    local cid="$1"
    [ -z "$cid" ] && echo "false" && return
    local mem
    mem=$(docker inspect "$cid" --format '{{.HostConfig.Memory}}' 2>/dev/null || echo "0")
    if [ -n "$mem" ] && [ "$mem" != "0" ]; then
        echo "true"
    else
        echo "false"
    fi
}

# --- Helper: check restart policy via docker inspect ---
check_restart_policy() {
    local cid="$1"
    [ -z "$cid" ] && echo "false" && return
    local restart
    restart=$(docker inspect "$cid" --format '{{.HostConfig.RestartPolicy.Name}}' 2>/dev/null || echo "")
    if echo "$restart" | grep -qE "^(unless-stopped|always|on-failure)$"; then
        echo "true"
    else
        echo "false"
    fi
}

# --- Check health checks ---
# First try docker inspect on running containers
NGINX_HAS_HEALTHCHECK=$(check_healthcheck "$NGINX_CID")
APP_HAS_HEALTHCHECK=$(check_healthcheck "$APP_CID")
REDIS_HAS_HEALTHCHECK=$(check_healthcheck "$REDIS_CID")

# Also check compose config (parsed output) for healthcheck keyword
COMPOSE_CONFIG=$(docker compose config 2>/dev/null || cat "$COMPOSE_FILE" 2>/dev/null || echo "")
TOTAL_HEALTHCHECKS=$(echo "$COMPOSE_CONFIG" | { grep -c "healthcheck:" 2>/dev/null; true; })

# If compose config shows healthchecks but containers haven't been restarted yet,
# count from compose config structure using awk to detect per-service
if [ "$TOTAL_HEALTHCHECKS" -ge 1 ]; then
    # Use awk to find which services have healthcheck in the resolved config
    # Look for pattern: "  servicename:" followed by healthcheck within that service's block
    NGINX_HC_COMPOSE=$(echo "$COMPOSE_CONFIG" | awk '
        /^  [a-z]/ { svc=substr($1,1,length($1)-1) }
        /healthcheck:/ && svc ~ /nginx/ { print "true"; exit }
    ')
    APP_HC_COMPOSE=$(echo "$COMPOSE_CONFIG" | awk '
        /^  [a-z]/ { svc=substr($1,1,length($1)-1) }
        /healthcheck:/ && svc ~ /^(app|flask|webapp|web|backend)$/ { print "true"; exit }
    ')
    REDIS_HC_COMPOSE=$(echo "$COMPOSE_CONFIG" | awk '
        /^  [a-z]/ { svc=substr($1,1,length($1)-1) }
        /healthcheck:/ && svc ~ /redis/ { print "true"; exit }
    ')
    [ "$NGINX_HC_COMPOSE" = "true" ] && NGINX_HAS_HEALTHCHECK="true"
    [ "$APP_HC_COMPOSE" = "true" ] && APP_HAS_HEALTHCHECK="true"
    [ "$REDIS_HC_COMPOSE" = "true" ] && REDIS_HAS_HEALTHCHECK="true"
fi

# Fallback: if total healthchecks match expected 3 services, mark all true
# (conservative: only if 3 healthchecks found in resolved config)
if [ "$TOTAL_HEALTHCHECKS" -ge 3 ]; then
    NGINX_HAS_HEALTHCHECK="true"
    APP_HAS_HEALTHCHECK="true"
    REDIS_HAS_HEALTHCHECK="true"
fi

SERVICES_WITH_HEALTHCHECK=$(( \
    $([ "$NGINX_HAS_HEALTHCHECK" = "true" ] && echo 1 || echo 0) + \
    $([ "$APP_HAS_HEALTHCHECK" = "true" ] && echo 1 || echo 0) + \
    $([ "$REDIS_HAS_HEALTHCHECK" = "true" ] && echo 1 || echo 0) \
))

# --- Check resource limits via docker inspect ---
NGINX_HAS_LIMITS=$(check_memory_limit "$NGINX_CID")
APP_HAS_LIMITS=$(check_memory_limit "$APP_CID")
REDIS_HAS_LIMITS=$(check_memory_limit "$REDIS_CID")

# Also check cpus limit
check_cpu_limit() {
    local cid="$1"
    [ -z "$cid" ] && echo "false" && return
    local cpu
    cpu=$(docker inspect "$cid" --format '{{.HostConfig.NanoCpus}}' 2>/dev/null || echo "0")
    if [ -n "$cpu" ] && [ "$cpu" != "0" ]; then
        echo "true"
    else
        echo "false"
    fi
}

[ "$(check_cpu_limit "$NGINX_CID")" = "true" ] && NGINX_HAS_LIMITS="true"
[ "$(check_cpu_limit "$APP_CID")" = "true" ] && APP_HAS_LIMITS="true"
[ "$(check_cpu_limit "$REDIS_CID")" = "true" ] && REDIS_HAS_LIMITS="true"

# Also check compose file for mem_limit / deploy resources
# (covers case where containers not yet restarted after compose change)
if grep -qE "mem_limit:|memory:" "$COMPOSE_FILE" 2>/dev/null; then
    MEM_IN_COMPOSE=$({ grep -c "memory:" "$COMPOSE_FILE" 2>/dev/null; true; })
    CPU_IN_COMPOSE=$({ grep -c "cpus:" "$COMPOSE_FILE" 2>/dev/null; true; })
    LIMIT_TOTAL=$((MEM_IN_COMPOSE + CPU_IN_COMPOSE))
    if [ "${LIMIT_TOTAL:-0}" -ge 3 ] || [ "${MEM_IN_COMPOSE:-0}" -ge 3 ]; then
        NGINX_HAS_LIMITS="true"; APP_HAS_LIMITS="true"; REDIS_HAS_LIMITS="true"
    fi
fi

SERVICES_WITH_LIMITS=$(( \
    $([ "$NGINX_HAS_LIMITS" = "true" ] && echo 1 || echo 0) + \
    $([ "$APP_HAS_LIMITS" = "true" ] && echo 1 || echo 0) + \
    $([ "$REDIS_HAS_LIMITS" = "true" ] && echo 1 || echo 0) \
))

# --- Check restart policies via docker inspect ---
NGINX_HAS_RESTART=$(check_restart_policy "$NGINX_CID")
APP_HAS_RESTART=$(check_restart_policy "$APP_CID")
REDIS_HAS_RESTART=$(check_restart_policy "$REDIS_CID")

# Also check compose file for restart: keyword
RESTART_COUNT=$({ grep -c "restart:" "$COMPOSE_FILE" 2>/dev/null; true; })
if [ "$RESTART_COUNT" -ge 3 ]; then
    NGINX_HAS_RESTART="true"; APP_HAS_RESTART="true"; REDIS_HAS_RESTART="true"
elif [ "$RESTART_COUNT" -ge 1 ]; then
    # Try to detect per-service from file
    if grep -A 20 "nginx:" "$COMPOSE_FILE" 2>/dev/null | grep -q "restart:"; then NGINX_HAS_RESTART="true"; fi
    if grep -A 20 "^  app:" "$COMPOSE_FILE" 2>/dev/null | grep -q "restart:"; then APP_HAS_RESTART="true"; fi
    if grep -A 20 "redis:" "$COMPOSE_FILE" 2>/dev/null | grep -q "restart:"; then REDIS_HAS_RESTART="true"; fi
fi

SERVICES_WITH_RESTART=$(( \
    $([ "$NGINX_HAS_RESTART" = "true" ] && echo 1 || echo 0) + \
    $([ "$APP_HAS_RESTART" = "true" ] && echo 1 || echo 0) + \
    $([ "$REDIS_HAS_RESTART" = "true" ] && echo 1 || echo 0) \
))

# --- Check network isolation ---
HAS_FRONTEND="false"
HAS_BACKEND="false"
REDIS_ONLY_BACKEND="false"

# Check docker networks for frontend/backend
if docker network ls --format "{{.Name}}" 2>/dev/null | grep -qi "front"; then HAS_FRONTEND="true"; fi
if docker network ls --format "{{.Name}}" 2>/dev/null | grep -qi "back"; then HAS_BACKEND="true"; fi

# Also check compose file
if grep -qE "^\s*frontend:" "$COMPOSE_FILE" 2>/dev/null || grep -qiE "front" "$COMPOSE_FILE" 2>/dev/null; then
    # Verify it's a network definition, not just mentioning "front"
    if grep -qE "^networks:" "$COMPOSE_FILE" 2>/dev/null; then
        if awk '/^networks:/,0' "$COMPOSE_FILE" 2>/dev/null | grep -qi "front"; then HAS_FRONTEND="true"; fi
        if awk '/^networks:/,0' "$COMPOSE_FILE" 2>/dev/null | grep -qi "back"; then HAS_BACKEND="true"; fi
    fi
fi

# Check if redis is only on backend (not on frontend)
if [ -n "$REDIS_CID" ]; then
    REDIS_NETWORKS=$(docker inspect "$REDIS_CID" --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}' 2>/dev/null || echo "")
    REDIS_ON_FRONT="false"
    REDIS_ON_BACK="false"
    echo "$REDIS_NETWORKS" | grep -qi "front" && REDIS_ON_FRONT="true"
    echo "$REDIS_NETWORKS" | grep -qi "back" && REDIS_ON_BACK="true"
    if [ "$REDIS_ON_BACK" = "true" ] && [ "$REDIS_ON_FRONT" = "false" ]; then
        REDIS_ONLY_BACKEND="true"
    fi
fi

# Fallback: check compose file for redis network assignment
if [ "$REDIS_ONLY_BACKEND" = "false" ] && grep -qiE "back" "$COMPOSE_FILE" 2>/dev/null; then
    # If redis service only lists backend network in compose file
    REDIS_SECTION=$(awk '/^  redis:/,/^  [a-z]/' "$COMPOSE_FILE" 2>/dev/null || echo "")
    if echo "$REDIS_SECTION" | grep -qi "back" && ! echo "$REDIS_SECTION" | grep -qi "front"; then
        REDIS_ONLY_BACKEND="true"
    fi
fi

# --- Check app accessible ---
APP_HTTP_CODE="000"
for i in 1 2 3 4 5; do
    CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 10 http://localhost:9080 2>/dev/null || echo "000")
    if [ "$CODE" = "200" ]; then
        APP_HTTP_CODE="$CODE"
        break
    fi
    sleep 2
done

cat > /tmp/compose_production_hardening_result.json << JSONEOF
{
    "compose_modified": $COMPOSE_MODIFIED,
    "nginx_has_healthcheck": $NGINX_HAS_HEALTHCHECK,
    "app_has_healthcheck": $APP_HAS_HEALTHCHECK,
    "redis_has_healthcheck": $REDIS_HAS_HEALTHCHECK,
    "services_with_healthcheck": $SERVICES_WITH_HEALTHCHECK,
    "nginx_has_limits": $NGINX_HAS_LIMITS,
    "app_has_limits": $APP_HAS_LIMITS,
    "redis_has_limits": $REDIS_HAS_LIMITS,
    "services_with_limits": $SERVICES_WITH_LIMITS,
    "nginx_has_restart": $NGINX_HAS_RESTART,
    "app_has_restart": $APP_HAS_RESTART,
    "redis_has_restart": $REDIS_HAS_RESTART,
    "services_with_restart": $SERVICES_WITH_RESTART,
    "has_frontend_network": $HAS_FRONTEND,
    "has_backend_network": $HAS_BACKEND,
    "redis_only_backend": $REDIS_ONLY_BACKEND,
    "app_http_code": "$APP_HTTP_CODE",
    "export_timestamp": "$(date -Iseconds)"
}
JSONEOF

echo "=== Export Complete ==="
cat /tmp/compose_production_hardening_result.json
