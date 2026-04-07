#!/bin/bash
echo "=== Exporting Task Results ==="

# Timestamp for verifying file creation time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Helper to check service status
check_service() {
    local svc="$1"
    local enabled="false"
    local active="false"
    local file_exists="false"
    local file_path="/etc/systemd/system/${svc}.service"
    local mtime=0
    
    if [ -f "$file_path" ]; then
        file_exists="true"
        mtime=$(stat -c %Y "$file_path")
    fi
    
    if systemctl is-enabled "$svc" >/dev/null 2>&1; then
        enabled="true"
    fi
    
    if systemctl is-active "$svc" >/dev/null 2>&1; then
        active="true"
    fi
    
    # Read content for dependency checking
    local content=""
    if [ "$file_exists" = "true" ]; then
        content=$(cat "$file_path" | base64 -w 0)
    fi

    echo "{\"name\": \"$svc\", \"exists\": $file_exists, \"enabled\": $enabled, \"active\": $active, \"mtime\": $mtime, \"content_b64\": \"$content\"}"
}

# 1. Check Unit Files & Systemd Status
DB_STATUS=$(check_service "acme-db")
API_STATUS=$(check_service "acme-api")
FRONT_STATUS=$(check_service "acme-frontend")

# 2. Check Docker Container Status
# We verify they are running AND their PID is managed by systemd (implicit check: if systemd verifies active, it's likely true, but we check docker ps too)
DB_RUNNING=$(docker ps --filter "name=acme-db" --format '{{.Status}}' | grep -i "Up" >/dev/null && echo "true" || echo "false")
API_RUNNING=$(docker ps --filter "name=acme-api" --format '{{.Status}}' | grep -i "Up" >/dev/null && echo "true" || echo "false")
FRONT_RUNNING=$(docker ps --filter "name=acme-frontend" --format '{{.Status}}' | grep -i "Up" >/dev/null && echo "true" || echo "false")

# 3. Functional Health Checks
# Check DB connectivity from API
DB_HEALTHY="false"
if [ "$API_RUNNING" = "true" ]; then
    HEALTH_RESP=$(docker exec acme-api curl -s http://localhost:5000/health || echo "")
    if echo "$HEALTH_RESP" | grep -q "connected"; then
        DB_HEALTHY="true"
    fi
fi

# Check Frontend Access
FRONT_HEALTHY="false"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/health || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
    FRONT_HEALTHY="true"
fi

# 4. Take Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 5. Compile JSON Result
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "services": {
        "db": $DB_STATUS,
        "api": $API_STATUS,
        "frontend": $FRONT_STATUS
    },
    "containers": {
        "db_running": $DB_RUNNING,
        "api_running": $API_RUNNING,
        "frontend_running": $FRONT_RUNNING
    },
    "functional": {
        "db_connected": $DB_HEALTHY,
        "frontend_accessible": $FRONT_HEALTHY
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json