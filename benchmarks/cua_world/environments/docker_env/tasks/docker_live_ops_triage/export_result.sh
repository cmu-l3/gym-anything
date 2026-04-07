#!/bin/bash
echo "=== Exporting Live Ops Results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Helper to inspect container
inspect_container() {
    docker inspect "$1" 2>/dev/null || echo "{}"
}

# 1. Capture Current State
WEB_INFO=$(inspect_container acme-web)
DB_INFO=$(inspect_container acme-db)
LB_INFO=$(inspect_container acme-lb)

# 2. Extract Uptime/Restart Info
# Start time from current state
WEB_CURRENT_START=$(echo "$WEB_INFO" | jq -r '.[0].State.StartedAt // empty')
DB_CURRENT_START=$(echo "$DB_INFO" | jq -r '.[0].State.StartedAt // empty')
LB_CURRENT_START=$(echo "$LB_INFO" | jq -r '.[0].State.StartedAt // empty')

# 3. Extract Resource Info (acme-web)
# Memory is in bytes, NanoCpus is in billionths
WEB_MEM=$(echo "$WEB_INFO" | jq -r '.[0].HostConfig.Memory // 0')
WEB_CPU=$(echo "$WEB_INFO" | jq -r '.[0].HostConfig.NanoCpus // 0')

# 4. Extract Network Info (acme-db)
# Check if "admin-net" key exists in Networks object
DB_NETWORKS=$(echo "$DB_INFO" | jq -r '.[0].NetworkSettings.Networks | keys | .[]')
HAS_ADMIN_NET=0
if echo "$DB_NETWORKS" | grep -q "admin-net"; then
    HAS_ADMIN_NET=1
fi

# 5. Extract Nginx Reload Info (acme-lb)
# We check if the server is actually serving the new config response
LB_RESPONSE=$(docker exec acme-lb curl -s localhost || echo "failed")
CONFIG_RELOADED=0
if [[ "$LB_RESPONSE" == *"New Config Loaded"* ]]; then
    CONFIG_RELOADED=1
fi

# 6. Read Initial State
INITIAL_WEB_START=$(jq -r '.web_start' /tmp/initial_state.json)
INITIAL_DB_START=$(jq -r '.db_start' /tmp/initial_state.json)
INITIAL_LB_START=$(jq -r '.lb_start' /tmp/initial_state.json)

# 7. Take Final Screenshot
if type take_screenshot &>/dev/null; then
    take_screenshot /tmp/task_final.png
else
    DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true
fi

# 8. Construct JSON Result
cat > /tmp/task_result.json <<EOF
{
    "initial_web_start": "$INITIAL_WEB_START",
    "current_web_start": "$WEB_CURRENT_START",
    "initial_db_start": "$INITIAL_DB_START",
    "current_db_start": "$DB_CURRENT_START",
    "initial_lb_start": "$INITIAL_LB_START",
    "current_lb_start": "$LB_CURRENT_START",
    
    "web_memory": $WEB_MEM,
    "web_cpu": $WEB_CPU,
    
    "db_has_admin_net": $HAS_ADMIN_NET,
    
    "lb_config_active": $CONFIG_RELOADED,
    
    "screenshot_path": "/tmp/task_final.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json