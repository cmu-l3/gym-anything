#!/bin/bash
echo "=== Exporting Registry Task Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true
take_screenshot /tmp/task_final.png

# Load start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# --- 1. Verify Registry Container ---
CONTAINER_NAME="acme-registry"
IS_RUNNING=0
PORT_MAPPING_CORRECT=0
VOLUME_MOUNTED=0

if [ "$(docker inspect -f '{{.State.Running}}' $CONTAINER_NAME 2>/dev/null)" == "true" ]; then
    IS_RUNNING=1
    
    # Check Port 5443->443
    # We look for "5443/tcp" in the bindings for 443/tcp
    if docker inspect $CONTAINER_NAME 2>/dev/null | grep -q "5443"; then
        PORT_MAPPING_CORRECT=1
    fi

    # Check Volume
    if docker inspect $CONTAINER_NAME 2>/dev/null | grep -q "registry-data:/var/lib/registry"; then
        VOLUME_MOUNTED=1
    fi
fi

# --- 2. Verify Files (Certs & Auth) ---
PROJECT_DIR="/home/ga/projects/registry-setup"
CERTS_EXIST=0
AUTH_EXISTS=0
CATALOG_SCRIPT_EXISTS=0

[ -f "$PROJECT_DIR/certs/domain.crt" ] && [ -f "$PROJECT_DIR/certs/domain.key" ] && CERTS_EXIST=1
[ -f "$PROJECT_DIR/auth/htpasswd" ] && AUTH_EXISTS=1
[ -f "$PROJECT_DIR/catalog.sh" ] && [ -x "$PROJECT_DIR/catalog.sh" ] && CATALOG_SCRIPT_EXISTS=1

# Check if htpasswd has correct users
AUTH_USERS_CORRECT=0
if [ "$AUTH_EXISTS" -eq 1 ]; then
    if grep -q "^admin:" "$PROJECT_DIR/auth/htpasswd" && grep -q "^ci-bot:" "$PROJECT_DIR/auth/htpasswd"; then
        AUTH_USERS_CORRECT=1
    fi
fi

# --- 3. Verify TLS & Auth via Connectivity ---
# We try to talk to the registry
TLS_WORKING=0
AUTH_ENFORCED=0
CATALOG_ACCESSIBLE=0

# Test TLS (insecure mode -k allowed because we know it's self-signed, 
# but we verify the service actually responds on HTTPS port)
HTTP_CODE_NO_AUTH=$(curl -s -o /dev/null -w "%{http_code}" -k https://registry.acme.local:5443/v2/ 2>/dev/null || echo "000")

if [ "$HTTP_CODE_NO_AUTH" != "000" ]; then
    TLS_WORKING=1
fi

if [ "$HTTP_CODE_NO_AUTH" == "401" ]; then
    AUTH_ENFORCED=1
fi

# Test Auth Success
HTTP_CODE_AUTH=$(curl -s -o /dev/null -w "%{http_code}" -k -u admin:RegistryAdmin2024 https://registry.acme.local:5443/v2/ 2>/dev/null || echo "000")
if [ "$HTTP_CODE_AUTH" == "200" ]; then
    CATALOG_ACCESSIBLE=1
fi

# --- 4. Verify Content (Catalog API) ---
REPO_COUNT=0
TAGS_CORRECT=0
API_JSON=""

if [ "$CATALOG_ACCESSIBLE" -eq 1 ]; then
    # Fetch catalog
    CATALOG_JSON=$(curl -s -k -u admin:RegistryAdmin2024 https://registry.acme.local:5443/v2/_catalog)
    
    # Simple grep check for repos
    HAS_API=$(echo "$CATALOG_JSON" | grep -c "acme/api-service")
    HAS_WEB=$(echo "$CATALOG_JSON" | grep -c "acme/web-frontend")
    HAS_PROXY=$(echo "$CATALOG_JSON" | grep -c "acme/reverse-proxy")
    
    if [ "$HAS_API" -eq 1 ] && [ "$HAS_WEB" -eq 1 ] && [ "$HAS_PROXY" -eq 1 ]; then
        REPO_COUNT=3
    fi

    # Check tags for one repo to verify
    TAGS_JSON=$(curl -s -k -u admin:RegistryAdmin2024 https://registry.acme.local:5443/v2/acme/api-service/tags/list)
    if echo "$TAGS_JSON" | grep -q "v1.2.0"; then
        TAGS_CORRECT=1
    fi
    # Assume if one matches and repos exist, user likely followed naming convention. 
    # Stricter verification can parse JSON in python.
fi

# --- 5. Verify Pull Test ---
# Check if the specific registry image exists locally (meaning it was pulled or built/tagged)
# The task requires removing it and pulling it.
# We check if the image ID matches the source image ID to ensure data integrity
SOURCE_ID=$(docker inspect --format '{{.Id}}' acme-api:latest 2>/dev/null)
TARGET_ID=$(docker inspect --format '{{.Id}}' registry.acme.local:5443/acme/api-service:v1.2.0 2>/dev/null)
IMAGE_INTEGRITY=0

if [ -n "$SOURCE_ID" ] && [ "$SOURCE_ID" == "$TARGET_ID" ]; then
    IMAGE_INTEGRITY=1
fi

# Generate JSON Result
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "is_running": $IS_RUNNING,
    "port_mapping_correct": $PORT_MAPPING_CORRECT,
    "volume_mounted": $VOLUME_MOUNTED,
    "certs_exist": $CERTS_EXIST,
    "auth_exists": $AUTH_EXISTS,
    "auth_users_correct": $AUTH_USERS_CORRECT,
    "catalog_script_exists": $CATALOG_SCRIPT_EXISTS,
    "tls_working": $TLS_WORKING,
    "auth_enforced": $AUTH_ENFORCED,
    "catalog_accessible": $CATALOG_ACCESSIBLE,
    "repo_count_correct": $([ "$REPO_COUNT" -eq 3 ] && echo "true" || echo "false"),
    "tags_correct": $TAGS_CORRECT,
    "image_integrity": $IMAGE_INTEGRITY,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Backup result to safe location with permissions
cp /tmp/task_result.json /tmp/safe_task_result.json
chmod 644 /tmp/safe_task_result.json

echo "Export complete. Result:"
cat /tmp/safe_task_result.json