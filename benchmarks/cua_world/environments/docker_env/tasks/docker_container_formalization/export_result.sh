#!/bin/bash
# Export script for docker_container_formalization
echo "=== Exporting Container Formalization Results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true
take_screenshot /tmp/task_end_screenshot.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
REPORT_PATH="/home/ga/Desktop/container_audit.txt"

# ------------------------------------------------------------------
# Helper Functions
# ------------------------------------------------------------------
check_image_exists() {
    docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "^$1$" && echo "true" || echo "false"
}

check_file_exists() {
    [ -f "$1" ] && echo "true" || echo "false"
}

# ------------------------------------------------------------------
# 1. Verify Frontend
# ------------------------------------------------------------------
FRONTEND_DF_EXISTS=$(check_file_exists "/home/ga/projects/reproducible-images/frontend/Dockerfile")
FRONTEND_IMG_EXISTS=$(check_image_exists "acme-frontend:reproducible")
FRONTEND_CONTENT_OK="false"
FRONTEND_HEALTH_OK="false"

if [ "$FRONTEND_IMG_EXISTS" == "true" ]; then
    echo "Testing acme-frontend:reproducible..."
    docker rm -f test-frontend 2>/dev/null || true
    docker run -d --name test-frontend -p 18080:80 acme-frontend:reproducible
    sleep 3
    
    # Check content
    CONTENT=$(curl -s http://localhost:18080/)
    if echo "$CONTENT" | grep -q "AcmeCorp Dashboard"; then
        FRONTEND_CONTENT_OK="true"
    fi
    
    # Check healthz config
    HEALTH=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:18080/healthz)
    if [ "$HEALTH" == "200" ]; then
        FRONTEND_HEALTH_OK="true"
    fi
    
    docker rm -f test-frontend 2>/dev/null || true
fi

# ------------------------------------------------------------------
# 2. Verify API
# ------------------------------------------------------------------
API_DF_EXISTS=$(check_file_exists "/home/ga/projects/reproducible-images/api/Dockerfile")
API_IMG_EXISTS=$(check_image_exists "acme-api:reproducible")
API_STATUS_OK="false"
API_DEPS_OK="false"

if [ "$API_IMG_EXISTS" == "true" ]; then
    echo "Testing acme-api:reproducible..."
    docker rm -f test-api 2>/dev/null || true
    docker run -d --name test-api -p 18000:8000 acme-api:reproducible
    sleep 5
    
    # Check endpoint
    STATUS_JSON=$(curl -s http://localhost:18000/api/status)
    if echo "$STATUS_JSON" | grep -q "acme-api"; then
        API_STATUS_OK="true"
    fi
    
    # Check installed packages (gunicorn/flask)
    if docker exec test-api pip list | grep -q "flask" && docker exec test-api pip list | grep -q "gunicorn"; then
        API_DEPS_OK="true"
    fi
    
    docker rm -f test-api 2>/dev/null || true
fi

# ------------------------------------------------------------------
# 3. Verify Cron
# ------------------------------------------------------------------
CRON_DF_EXISTS=$(check_file_exists "/home/ga/projects/reproducible-images/cron/Dockerfile")
CRON_IMG_EXISTS=$(check_image_exists "acme-cron:reproducible")
CRON_TOOLS_OK="false"
CRON_SCRIPT_OK="false"

if [ "$CRON_IMG_EXISTS" == "true" ]; then
    echo "Testing acme-cron:reproducible..."
    docker rm -f test-cron 2>/dev/null || true
    # Run a command to keep it alive for checking
    docker run -d --name test-cron acme-cron:reproducible sleep 60
    
    # Check tools
    if docker exec test-cron which bash && docker exec test-cron which curl && docker exec test-cron which jq; then
        CRON_TOOLS_OK="true"
    fi
    
    # Check script existence
    if docker exec test-cron [ -f /app/healthcheck.sh ]; then
        CRON_SCRIPT_OK="true"
    fi
    
    docker rm -f test-cron 2>/dev/null || true
fi

# ------------------------------------------------------------------
# 4. Check Audit Report
# ------------------------------------------------------------------
REPORT_EXISTS="false"
REPORT_SIZE=0
REPORT_MENTIONS=0

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(wc -c < "$REPORT_PATH")
    if grep -q "acme-frontend" "$REPORT_PATH" && grep -q "acme-api" "$REPORT_PATH" && grep -q "acme-cron" "$REPORT_PATH"; then
        REPORT_MENTIONS=1
    fi
fi

# ------------------------------------------------------------------
# Export JSON
# ------------------------------------------------------------------
cat > /tmp/formalization_result.json <<EOF
{
  "task_start": $TASK_START,
  "frontend": {
    "dockerfile_exists": $FRONTEND_DF_EXISTS,
    "image_exists": $FRONTEND_IMG_EXISTS,
    "content_match": $FRONTEND_CONTENT_OK,
    "config_match": $FRONTEND_HEALTH_OK
  },
  "api": {
    "dockerfile_exists": $API_DF_EXISTS,
    "image_exists": $API_IMG_EXISTS,
    "status_endpoint": $API_STATUS_OK,
    "dependencies": $API_DEPS_OK
  },
  "cron": {
    "dockerfile_exists": $CRON_DF_EXISTS,
    "image_exists": $CRON_IMG_EXISTS,
    "tools_installed": $CRON_TOOLS_OK,
    "script_exists": $CRON_SCRIPT_OK
  },
  "report": {
    "exists": $REPORT_EXISTS,
    "size": $REPORT_SIZE,
    "mentions_all": $REPORT_MENTIONS
  }
}
EOF

echo "Result JSON written to /tmp/formalization_result.json"
cat /tmp/formalization_result.json
echo "=== Export Complete ==="