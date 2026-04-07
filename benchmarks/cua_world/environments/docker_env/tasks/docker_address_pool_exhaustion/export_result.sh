#!/bin/bash
echo "=== Exporting Docker Address Pool Results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Timestamp
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check Docker Daemon Status
DOCKER_RUNNING="false"
if docker info >/dev/null 2>&1; then
    DOCKER_RUNNING="true"
fi

# 2. Capture Daemon Config
DAEMON_CONFIG_CONTENT=""
CONFIG_MODIFIED="false"
if [ -f /etc/docker/daemon.json ]; then
    DAEMON_CONFIG_CONTENT=$(cat /etc/docker/daemon.json)
    
    # Check modification time
    CONFIG_MTIME=$(stat -c %Y /etc/docker/daemon.json 2>/dev/null || echo "0")
    if [ "$CONFIG_MTIME" -gt "$TASK_START" ]; then
        CONFIG_MODIFIED="true"
    fi
fi

# 3. Check Container Status
PROD_RUNNING="false"
TEST_RUNNING="false"

if docker ps --format '{{.Names}}' | grep -q "^acme-prod$"; then
    PROD_RUNNING="true"
fi

if docker ps --format '{{.Names}}' | grep -q "^acme-ci-test$"; then
    TEST_RUNNING="true"
fi

# 4. Check Network Isolation
# Get IP Address / Subnet for both
PROD_NET=$(docker inspect acme-prod --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null || echo "")
TEST_NET=$(docker inspect acme-ci-test --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null || echo "")

# 5. Take Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 6. Generate JSON Result
cat > /tmp/task_result.json <<EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "docker_running": $DOCKER_RUNNING,
    "config_modified": $CONFIG_MODIFIED,
    "daemon_config": $(echo "$DAEMON_CONFIG_CONTENT" | jq -R .),
    "prod_running": $PROD_RUNNING,
    "test_running": $TEST_RUNNING,
    "prod_ip": "$PROD_NET",
    "test_ip": "$TEST_NET",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Set permissions so python verifier can read it
chmod 644 /tmp/task_result.json

echo "Export complete."
cat /tmp/task_result.json