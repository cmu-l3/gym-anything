#!/bin/bash
# Export script for docker_incident_rca task

echo "=== Exporting Incident RCA Results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true
take_screenshot /tmp/task_end.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# 1. Check Service Status
DB_RUNNING=$(docker inspect -f '{{.State.Running}}' store-db 2>/dev/null || echo "false")
API_RUNNING=$(docker inspect -f '{{.State.Running}}' store-api 2>/dev/null || echo "false")
WORKER_RUNNING=$(docker inspect -f '{{.State.Running}}' store-worker 2>/dev/null || echo "false")
WEB_RUNNING=$(docker inspect -f '{{.State.Running}}' store-web 2>/dev/null || echo "false")

# 2. Check Database Configuration (The Fix)
# We expect max_connections to be raised significantly (default is usually 100, we set 5 to break it)
# Agent should have changed it to at least 20.
MAX_CONNS=0
if [ "$DB_RUNNING" = "true" ]; then
    MAX_CONNS=$(docker exec store-db psql -U storeuser -d storedb -tAc "SHOW max_connections;" 2>/dev/null || echo "0")
fi

# 3. Check API Availability
API_STATUS="000"
if [ "$WEB_RUNNING" = "true" ]; then
    API_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/api/health 2>/dev/null || echo "000")
fi

# 4. Check Incident Report
REPORT_PATH="/home/ga/Desktop/incident_report.txt"
REPORT_EXISTS="false"
REPORT_MTIME=0
REPORT_CONTENT=""

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    # Read content for python verification (sanitize newlines)
    REPORT_CONTENT=$(cat "$REPORT_PATH" | tr '\n' ' ' | sed 's/"/\\"/g')
fi

# 5. Export JSON
cat > /tmp/rca_result.json <<EOF
{
    "task_start": $TASK_START,
    "db_running": $DB_RUNNING,
    "api_running": $API_RUNNING,
    "worker_running": $WORKER_RUNNING,
    "web_running": $WEB_RUNNING,
    "db_max_connections": "$MAX_CONNS",
    "api_http_status": "$API_STATUS",
    "report_exists": $REPORT_EXISTS,
    "report_mtime": $REPORT_MTIME,
    "report_content_preview": "$REPORT_CONTENT",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Export completed:"
cat /tmp/rca_result.json
echo "=== Export Complete ==="