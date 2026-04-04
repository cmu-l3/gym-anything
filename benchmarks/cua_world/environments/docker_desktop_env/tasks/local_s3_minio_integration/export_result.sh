#!/bin/bash
# Export script for local_s3_minio_integration task

echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
PROJECT_DIR="/home/ga/s3-project"

# Take final screenshot
take_screenshot /tmp/task_final.png

# --- Verification Variables ---
SERVICES_RUNNING="false"
BUCKET_EXISTS="false"
UPLOAD_SUCCESS="false"
ENV_CONFIGURED="false"
TEST_FILENAME="test_verify_$(date +%s).txt"

# 1. Check if services are running via Docker Compose
cd "$PROJECT_DIR" || exit 1
RUNNING_SERVICES=$(docker compose ps --services --filter "status=running" 2>/dev/null | sort)
EXPECTED_SERVICES="web" # MinIO name might vary, but we look for web

if echo "$RUNNING_SERVICES" | grep -q "web"; then
    SERVICES_RUNNING="true"
fi

# Detect MinIO service name (agent might name it minio, s3, etc)
MINIO_SERVICE_NAME=$(docker compose ps --services 2>/dev/null | grep -E "minio|s3" | head -n 1)

# 2. Check Environment Variables in Web Container
if [ "$SERVICES_RUNNING" = "true" ]; then
    WEB_ENV=$(docker compose exec -T web env 2>/dev/null)
    
    HAS_ENDPOINT=$(echo "$WEB_ENV" | grep "S3_ENDPOINT_URL=")
    HAS_KEY=$(echo "$WEB_ENV" | grep "AWS_ACCESS_KEY_ID=")
    HAS_SECRET=$(echo "$WEB_ENV" | grep "AWS_SECRET_ACCESS_KEY=")
    
    if [ -n "$HAS_ENDPOINT" ] && [ -n "$HAS_KEY" ] && [ -n "$HAS_SECRET" ]; then
        ENV_CONFIGURED="true"
    fi
fi

# 3. Verify Bucket Existence & Persistence (from INSIDE the web container)
# We use the web container to verify because it has boto3 installed and has access to the docker network
if [ "$SERVICES_RUNNING" = "true" ] && [ "$ENV_CONFIGURED" = "true" ]; then
    
    # Create a python verification script inside the container
    cat > /tmp/verify_internal.py << 'PYEOF'
import os
import boto3
import sys

try:
    endpoint = os.environ.get('S3_ENDPOINT_URL')
    key = os.environ.get('AWS_ACCESS_KEY_ID')
    secret = os.environ.get('AWS_SECRET_ACCESS_KEY')
    
    if not endpoint:
        print("MISSING_ENV")
        sys.exit(1)

    s3 = boto3.client('s3', endpoint_url=endpoint, aws_access_key_id=key, aws_secret_access_key=secret, region_name='us-east-1')
    
    # Check bucket existence
    buckets = [b['Name'] for b in s3.list_buckets().get('Buckets', [])]
    if 'company-assets' in buckets:
        print("BUCKET_FOUND")
    else:
        print(f"BUCKET_MISSING: Found {buckets}")

except Exception as e:
    print(f"ERROR: {e}")
PYEOF

    # Copy script to container
    docker cp /tmp/verify_internal.py "$(docker compose ps -q web):/app/verify_internal.py"
    
    # Run script
    VERIFY_OUTPUT=$(docker compose exec -T web python /app/verify_internal.py 2>/dev/null)
    
    if echo "$VERIFY_OUTPUT" | grep -q "BUCKET_FOUND"; then
        BUCKET_EXISTS="true"
    fi
    
    echo "Internal Verification Output: $VERIFY_OUTPUT"
fi

# 4. End-to-End Upload Test via Web App
# This proves the app is actually connected and working
if [ "$SERVICES_RUNNING" = "true" ]; then
    # Create dummy file
    echo "Verification test content $(date)" > "/tmp/$TEST_FILENAME"
    
    # Try upload
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST -F "file=@/tmp/$TEST_FILENAME" http://localhost:5000/upload)
    
    if [ "$HTTP_CODE" = "200" ]; then
        # Double check: Does the file exist in the bucket now?
        # Re-use the internal verification script logic
        CHECK_FILE_CMD="import boto3, os; s3 = boto3.client('s3', endpoint_url=os.environ.get('S3_ENDPOINT_URL'), aws_access_key_id=os.environ.get('AWS_ACCESS_KEY_ID'), aws_secret_access_key=os.environ.get('AWS_SECRET_ACCESS_KEY')); s3.head_object(Bucket='company-assets', Key='$TEST_FILENAME')"
        
        if docker compose exec -T web python -c "$CHECK_FILE_CMD" 2>/dev/null; then
             UPLOAD_SUCCESS="true"
        fi
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "services_running": $SERVICES_RUNNING,
    "minio_service_name": "$MINIO_SERVICE_NAME",
    "env_configured": $ENV_CONFIGURED,
    "bucket_exists": $BUCKET_EXISTS,
    "upload_success": $UPLOAD_SUCCESS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export complete ==="
cat /tmp/task_result.json