#!/bin/bash
# export_result.sh — post_task hook for fix_broken_server_config

echo "=== Exporting fix_broken_server_config result ==="

# 1. Capture final state
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
EXPECTED_COUNT=$(cat /tmp/expected_aircraft_count.txt 2>/dev/null || echo "0")

# 2. Check Service Status
SERVICE_ACTIVE=$(systemctl is-active aerobridge 2>/dev/null || echo "inactive")
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/admin/ 2>/dev/null || echo "000")

# 3. Analyze .env file
ENV_FILE="/opt/aerobridge/.env"
CURRENT_SALT=""
VALID_FERNET="false"
KEY_CHANGED="false"

if [ -f "$ENV_FILE" ]; then
    # Extract salt value
    CURRENT_SALT=$(grep "^CRYPTOGRAPHY_SALT" "$ENV_FILE" | cut -d'=' -f2 | tr -d "'\"" | tr -d '[:space:]')
    
    # Check if changed from broken value
    if [ "$CURRENT_SALT" != "INVALID_BROKEN_KEY_CORRUPTED_VALUE" ]; then
        KEY_CHANGED="true"
    fi

    # Check validity using python
    VALID_FERNET=$(/opt/aerobridge_venv/bin/python3 -c "
try:
    from cryptography.fernet import Fernet
    import sys
    key = '$CURRENT_SALT'
    try:
        Fernet(key.encode())
        print('true')
    except Exception:
        print('false')
except:
    print('error')
" 2>/dev/null || echo "error")
fi

# 4. Check Verification File (Anti-Gaming)
VERIFY_FILE="/home/ga/repair_verification.txt"
FILE_EXISTS="false"
FILE_CONTENT=""
FILE_TIMESTAMP="0"
FILE_CREATED_DURING_TASK="false"
COUNT_CORRECT="false"

if [ -f "$VERIFY_FILE" ]; then
    FILE_EXISTS="true"
    FILE_CONTENT=$(cat "$VERIFY_FILE" | tr -d '[:space:]')
    FILE_TIMESTAMP=$(stat -c %Y "$VERIFY_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_TIMESTAMP" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    if [ "$FILE_CONTENT" == "$EXPECTED_COUNT" ]; then
        COUNT_CORRECT="true"
    fi
fi

# 5. Check Database Operability
DB_WORKING="false"
if [ "$SERVICE_ACTIVE" == "active" ]; then
    # Try a quick DB query
    cd /opt/aerobridge
    DB_CHECK=$(/opt/aerobridge_venv/bin/python3 -c "
import os, sys, django
sys.path.insert(0, '/opt/aerobridge')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'aerobridge.settings')
try:
    with open('/opt/aerobridge/.env') as f:
        for line in f:
            if '=' in line and not line.strip().startswith('#'):
                k,_,v = line.partition('=')
                os.environ.setdefault(k.strip(), v.strip().strip(\"'\\\"\"))
    django.setup()
    from registry.models import Aircraft
    print('ok')
except:
    print('fail')
" 2>/dev/null || echo "fail")
    
    if [ "$DB_CHECK" == "ok" ]; then
        DB_WORKING="true"
    fi
fi

# 6. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "service_active": "$SERVICE_ACTIVE",
    "http_status": "$HTTP_STATUS",
    "key_changed": $KEY_CHANGED,
    "valid_fernet": $VALID_FERNET,
    "db_working": $DB_WORKING,
    "verification_file_exists": $FILE_EXISTS,
    "verification_file_content": "$FILE_CONTENT",
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "count_correct": $COUNT_CORRECT,
    "expected_count": "$EXPECTED_COUNT"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="