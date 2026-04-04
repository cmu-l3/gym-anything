#!/bin/bash
echo "=== Exporting Credential Rotation Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Config
PROJECT_DIR="/home/ga/app-stack"
DB_Container="appstack-db"
NEW_PASS="SecureNewPass!2024"
OLD_PASS="oldpass123"
DB_USER="appuser"
DB_NAME="appdb"

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Check Database Connectivity (The Core Test)

# Check A: Can we login with NEW password?
# We use PGPASSWORD env var to avoid prompt issues
CAN_LOGIN_NEW="false"
if PGPASSWORD="$NEW_PASS" docker exec -e PGPASSWORD="$NEW_PASS" "$DB_Container" psql -U "$DB_USER" -d "$DB_NAME" -c "\q" 2>/dev/null; then
    CAN_LOGIN_NEW="true"
fi

# Check B: Can we login with OLD password? (Should fail)
CAN_LOGIN_OLD="false"
if PGPASSWORD="$OLD_PASS" docker exec -e PGPASSWORD="$OLD_PASS" "$DB_Container" psql -U "$DB_USER" -d "$DB_NAME" -c "\q" 2>/dev/null; then
    CAN_LOGIN_OLD="true"
fi

# 3. Check Data Integrity
DATA_ROWS_COUNT="0"
# Only try to count if we can login (prefer new pass, fallback to old to detect if they just didn't change it but kept data)
if [ "$CAN_LOGIN_NEW" = "true" ]; then
    DATA_ROWS_COUNT=$(docker exec -e PGPASSWORD="$NEW_PASS" "$DB_Container" psql -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT COUNT(*) FROM projects;" 2>/dev/null | xargs || echo "0")
elif [ "$CAN_LOGIN_OLD" = "true" ]; then
    DATA_ROWS_COUNT=$(docker exec -e PGPASSWORD="$OLD_PASS" "$DB_Container" psql -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT COUNT(*) FROM projects;" 2>/dev/null | xargs || echo "0")
fi

# 4. Check Docker Compose Configuration
COMPOSE_FILE="$PROJECT_DIR/docker-compose.yml"
COMPOSE_UPDATED_DB="false"
COMPOSE_UPDATED_ADMINER="false"
COMPOSE_HAS_OLD_PASS="false"

if [ -f "$COMPOSE_FILE" ]; then
    # Check for new password string
    if grep -q "$NEW_PASS" "$COMPOSE_FILE"; then
        # Check specific sections roughly
        if grep -A 10 "services:" "$COMPOSE_FILE" | grep -A 10 "db:" | grep -q "$NEW_PASS"; then
            COMPOSE_UPDATED_DB="true"
        fi
        if grep -A 10 "adminer:" "$COMPOSE_FILE" | grep -q "$NEW_PASS"; then
            COMPOSE_UPDATED_ADMINER="true"
        fi
    fi
    
    # Check if old password is still lingering
    if grep -q "$OLD_PASS" "$COMPOSE_FILE"; then
        COMPOSE_HAS_OLD_PASS="true"
    fi
fi

# 5. Check Service Status
SERVICES_RUNNING="false"
ADMINER_ACCESSIBLE="false"

# Check if containers are running
if [ "$(docker inspect -f '{{.State.Running}}' appstack-db 2>/dev/null)" = "true" ] && \
   [ "$(docker inspect -f '{{.State.Running}}' appstack-adminer 2>/dev/null)" = "true" ]; then
    SERVICES_RUNNING="true"
fi

# Check Adminer HTTP
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8081 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
    ADMINER_ACCESSIBLE="true"
fi

# 6. Check File Modification Time (Anti-Gaming)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
COMPOSE_MOD_TIME=$(stat -c %Y "$COMPOSE_FILE" 2>/dev/null || echo "0")
FILE_MODIFIED_AFTER_START="false"
if [ "$COMPOSE_MOD_TIME" -gt "$TASK_START" ]; then
    FILE_MODIFIED_AFTER_START="true"
fi

# 7. Generate JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "can_login_new_pass": $CAN_LOGIN_NEW,
    "can_login_old_pass": $CAN_LOGIN_OLD,
    "data_rows_count": ${DATA_ROWS_COUNT:-0},
    "compose_updated_db": $COMPOSE_UPDATED_DB,
    "compose_updated_adminer": $COMPOSE_UPDATED_ADMINER,
    "compose_has_old_pass": $COMPOSE_HAS_OLD_PASS,
    "services_running": $SERVICES_RUNNING,
    "adminer_accessible": $ADMINER_ACCESSIBLE,
    "file_modified_after_start": $FILE_MODIFIED_AFTER_START,
    "screenshot_path": "/tmp/task_final.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json