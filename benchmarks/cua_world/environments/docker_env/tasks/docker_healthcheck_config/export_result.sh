#!/bin/bash
set -e
echo "=== Exporting Healthcheck Config Results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Helper to inspect container
get_container_info() {
    local name="$1"
    local info
    info=$(docker inspect "$name" 2>/dev/null) || { echo '{"exists": false, "running": false, "health_status": "none", "has_healthcheck": false, "restart_policy": "no"}'; return; }

    python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    c = data[0]
    state = c.get('State', {})
    health = state.get('Health', {})
    config = c.get('Config', {})
    host_config = c.get('HostConfig', {})
    hc = config.get('Healthcheck', None)
    rp = host_config.get('RestartPolicy', {})

    result = {
        'exists': True,
        'running': state.get('Running', False),
        'health_status': health.get('Status', 'none'),
        # Check if Test command is present and not empty
        'has_healthcheck': bool(hc and hc.get('Test')),
        'restart_policy': rp.get('Name', 'no')
    }
    print(json.dumps(result))
except Exception:
    print('{\"exists\": false, \"running\": false, \"health_status\": \"none\", \"has_healthcheck\": false, \"restart_policy\": \"no\"}')
" <<< "$info"
}

# Collect info for all services
CATALOG_INFO=$(get_container_info "healthlab-catalog")
ORDERS_INFO=$(get_container_info "healthlab-orders")
DB_INFO=$(get_container_info "healthlab-db")
CACHE_INFO=$(get_container_info "healthlab-cache")

# Check evidence file
REPORT_PATH="/home/ga/Desktop/health_status.txt"
REPORT_EXISTS="false"
REPORT_HAS_CONTENT="false"
REPORT_AFTER_START="false"
REPORT_MENTIONS_HEALTHY="false"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(wc -c < "$REPORT_PATH")
    if [ "$REPORT_SIZE" -gt 20 ]; then
        REPORT_HAS_CONTENT="true"
    fi
    
    TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
    FILE_TIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_TIME" -gt "$TASK_START" ]; then
        REPORT_AFTER_START="true"
    fi
    
    if grep -qi "healthy" "$REPORT_PATH"; then
        REPORT_MENTIONS_HEALTHY="true"
    fi
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create result JSON
cat > /tmp/healthcheck_results.json << ENDJSON
{
    "catalog": $CATALOG_INFO,
    "orders": $ORDERS_INFO,
    "db": $DB_INFO,
    "cache": $CACHE_INFO,
    "report": {
        "exists": $REPORT_EXISTS,
        "has_content": $REPORT_HAS_CONTENT,
        "after_start": $REPORT_AFTER_START,
        "mentions_healthy": $REPORT_MENTIONS_HEALTHY
    },
    "timestamp": "$(date -Iseconds)"
}
ENDJSON

# Permissions
chmod 666 /tmp/healthcheck_results.json

echo "=== Export Complete ==="
cat /tmp/healthcheck_results.json