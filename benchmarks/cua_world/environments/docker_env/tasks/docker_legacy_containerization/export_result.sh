#!/bin/bash
echo "=== Exporting Task Results ==="

# Define paths and timestamps
PROJECT_DIR="/home/ga/projects/bookstore-legacy"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULT_FILE="/tmp/task_result.json"

# Function to check file existence
check_file() {
    if [ -f "$1" ]; then echo "true"; else echo "false"; fi
}

# 1. File Existence Checks
HAS_DOCKERFILE=$(check_file "$PROJECT_DIR/Dockerfile")
HAS_COMPOSE=$(check_file "$PROJECT_DIR/docker-compose.yml")

# 2. Docker Container Checks
# Get list of running container names from the compose project
# Assuming agent runs 'docker compose up', names usually contain project dir name or are defined in compose
CONTAINERS=$(docker ps --format '{{.Names}}' | grep "bookstore" || echo "")
# Fallback: check generally for likely service names if project name varies
if [ -z "$CONTAINERS" ]; then
    CONTAINERS=$(docker ps --format '{{.Names}}')
fi

RUNNING_COUNT=$(echo "$CONTAINERS" | wc -l)

HAS_DB_CONTAINER="false"
HAS_API_CONTAINER="false"
HAS_NGINX_CONTAINER="false"

if echo "$CONTAINERS" | grep -qiE "db|postgres|database"; then HAS_DB_CONTAINER="true"; fi
if echo "$CONTAINERS" | grep -qiE "api|app|flask|web"; then HAS_API_CONTAINER="true"; fi
if echo "$CONTAINERS" | grep -qiE "nginx|proxy"; then HAS_NGINX_CONTAINER="true"; fi

# 3. Application Functionality Check (Wait for startup)
echo "Waiting for services to respond..."
sleep 5

# Check Nginx landing page
HTTP_ROOT_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/)
HTTP_ROOT_BODY=$(curl -s http://localhost/ | head -n 5)
if [ "$HTTP_ROOT_CODE" == "200" ] && echo "$HTTP_ROOT_BODY" | grep -qi "html"; then
    ROOT_OK="true"
else
    ROOT_OK="false"
fi

# Check API Endpoint
HTTP_API_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/api/books)
API_RESPONSE=$(curl -s http://localhost/api/books)

# Check if API returns JSON array
if [ "$HTTP_API_CODE" == "200" ] && echo "$API_RESPONSE" | grep -q "\[.*\]"; then
    API_OK="true"
else
    API_OK="false"
fi

# Check Content (Specific books from seed)
CONTENT_CHECK="false"
if echo "$API_RESPONSE" | grep -q "Pride and Prejudice" && echo "$API_RESPONSE" | grep -q "Moby-Dick"; then
    CONTENT_CHECK="true"
fi

# 4. Database Integrity Check
# Try to identify the DB container ID to run exec
DB_ID=$(docker ps -q --filter "ancestor=postgres:15" | head -n 1)
if [ -z "$DB_ID" ]; then
    DB_ID=$(docker ps -q --filter "ancestor=postgres" | head -n 1)
fi

DB_ROW_COUNT=0
if [ -n "$DB_ID" ]; then
    # Try to count rows in book table. User might be 'bookstore' or 'postgres'
    DB_ROW_COUNT=$(docker exec "$DB_ID" psql -U bookstore -d bookstore -t -c "SELECT COUNT(*) FROM book;" 2>/dev/null | tr -d '[:space:]' || echo "0")
    if [ "$DB_ROW_COUNT" == "0" ]; then
         # Try fallback user/db if they changed it
         DB_ROW_COUNT=$(docker exec "$DB_ID" psql -U postgres -t -c "SELECT COUNT(*) FROM book;" 2>/dev/null | tr -d '[:space:]' || echo "0")
    fi
fi

# 5. Take Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Construct JSON
cat > "$RESULT_FILE" << EOF
{
    "task_start": $TASK_START,
    "has_dockerfile": $HAS_DOCKERFILE,
    "has_compose": $HAS_COMPOSE,
    "running_containers_count": $RUNNING_COUNT,
    "has_db_container": $HAS_DB_CONTAINER,
    "has_api_container": $HAS_API_CONTAINER,
    "has_nginx_container": $HAS_NGINX_CONTAINER,
    "root_endpoint_ok": $ROOT_OK,
    "api_endpoint_ok": $API_OK,
    "content_correct": $CONTENT_CHECK,
    "db_row_count": "$DB_ROW_COUNT",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Safe copy/permissions
chmod 644 "$RESULT_FILE"
echo "Export complete. Result:"
cat "$RESULT_FILE"