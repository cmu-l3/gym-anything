#!/bin/bash
echo "=== Exporting Task Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Capture final state
take_screenshot /tmp/task_final.png

# Timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

PROJECT_DIR="/home/ga/projects/acme-store"
REPORT_PATH="/home/ga/Desktop/secrets_audit_report.txt"

# ------------------------------------------------------------------------------
# 1. VERIFY CONTAINER STATE & ENV VARS (The most critical checks)
# ------------------------------------------------------------------------------

# Helper to check if a string exists in a container's inspect output
# Returns "found" if the secret is present (BAD), "clean" if absent (GOOD)
check_env_for_secret() {
    local container=$1
    local secret_val=$2
    if docker inspect "$container" 2>/dev/null | grep -q "$secret_val"; then
        echo "found"
    else
        echo "clean"
    fi
}

# Check DB
DB_STATUS=$(get_container_status "acme-db")
DB_ENV_CHECK=$(check_env_for_secret "acme-db" "SuperSecret123!")

# Check Cache (Command line often reveals secrets in Redis)
CACHE_STATUS=$(get_container_status "acme-cache")
CACHE_CMD_CHECK=$(check_env_for_secret "acme-cache" "RedisPass456")

# Check API
API_STATUS=$(get_container_status "acme-api")
API_ENV_DB_CHECK=$(check_env_for_secret "acme-api" "SuperSecret123!")
API_ENV_REDIS_CHECK=$(check_env_for_secret "acme-api" "RedisPass456")
API_ENV_STRIPE_CHECK=$(check_env_for_secret "acme-api" "sk_live_a1b2c3d4e5f6g7h8i9j0")
API_ENV_FLASK_CHECK=$(check_env_for_secret "acme-api" "my_flask_secret_key_2024")

# Check Web
WEB_STATUS=$(get_container_status "acme-web")

# ------------------------------------------------------------------------------
# 2. VERIFY SECRETS CONFIGURATION
# ------------------------------------------------------------------------------

# Check for secrets directory
SECRETS_DIR_EXISTS="false"
SECRET_FILE_COUNT=0
if [ -d "$PROJECT_DIR/secrets" ]; then
    SECRETS_DIR_EXISTS="true"
    SECRET_FILE_COUNT=$(ls -1 "$PROJECT_DIR/secrets" | wc -l)
fi

# Check docker-compose.yml for "secrets:" block
COMPOSE_HAS_SECRETS="false"
if grep -q "^secrets:" "$PROJECT_DIR/docker-compose.yml" 2>/dev/null; then
    COMPOSE_HAS_SECRETS="true"
fi

# ------------------------------------------------------------------------------
# 3. VERIFY FUNCTIONALITY
# ------------------------------------------------------------------------------

# Wait a moment for services to settle if they just started
sleep 2

API_RESPONSE_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/api/products)
API_RESPONSE_BODY=$(curl -s http://localhost:8080/api/products)
HEALTH_RESPONSE_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/health)

# Check if JSON valid
IS_VALID_JSON="false"
if echo "$API_RESPONSE_BODY" | jq . >/dev/null 2>&1; then
    IS_VALID_JSON="true"
fi

# ------------------------------------------------------------------------------
# 4. VERIFY REPORT
# ------------------------------------------------------------------------------
REPORT_EXISTS="false"
REPORT_SIZE=0
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH")
fi

# ------------------------------------------------------------------------------
# COMPILE RESULT
# ------------------------------------------------------------------------------

# Use temp file to avoid permission issues
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "timestamp": "$(date -Iseconds)",
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "containers": {
        "db_status": "$DB_STATUS",
        "cache_status": "$CACHE_STATUS",
        "api_status": "$API_STATUS",
        "web_status": "$WEB_STATUS"
    },
    "secrets_audit": {
        "db_env_has_secret": "$DB_ENV_CHECK",
        "cache_cmd_has_secret": "$CACHE_CMD_CHECK",
        "api_env_db_secret": "$API_ENV_DB_CHECK",
        "api_env_redis_secret": "$API_ENV_REDIS_CHECK",
        "api_env_stripe_secret": "$API_ENV_STRIPE_CHECK",
        "api_env_flask_secret": "$API_ENV_FLASK_CHECK"
    },
    "configuration": {
        "secrets_dir_exists": $SECRETS_DIR_EXISTS,
        "secret_file_count": $SECRET_FILE_COUNT,
        "compose_defines_secrets": $COMPOSE_HAS_SECRETS
    },
    "functionality": {
        "api_http_code": "$API_RESPONSE_CODE",
        "health_http_code": "$HEALTH_RESPONSE_CODE",
        "valid_json_response": $IS_VALID_JSON
    },
    "report": {
        "exists": $REPORT_EXISTS,
        "size_bytes": $REPORT_SIZE
    }
}
EOF

# Safe move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json