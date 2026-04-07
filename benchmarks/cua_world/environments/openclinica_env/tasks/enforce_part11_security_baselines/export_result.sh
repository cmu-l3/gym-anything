#!/bin/bash
echo "=== Exporting enforce_part11_security_baselines result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot before stopping anything
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

echo "Checking application health..."
# Allow time for Tomcat to restart if the agent just issued the restart command
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "http://localhost:8080/OpenClinica/" || echo "000")

if [ "$HTTP_CODE" != "200" ] && [ "$HTTP_CODE" != "302" ]; then
    echo "App not immediately responding ($HTTP_CODE). Waiting up to 60s for Tomcat to finish restarting..."
    for i in {1..12}; do
        sleep 5
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://localhost:8080/OpenClinica/" || echo "000")
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
            echo "Application is back online ($HTTP_CODE)."
            break
        fi
    done
fi

APP_HEALTHY="false"
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
    APP_HEALTHY="true"
else
    echo "WARNING: Application failed to come back online (HTTP $HTTP_CODE)."
fi

# Extract datainfo.properties file to host so verifier can parse it safely
echo "Extracting configuration file..."
docker exec oc-app cat /usr/local/tomcat/webapps/OpenClinica/WEB-INF/classes/datainfo.properties > /tmp/datainfo.properties 2>/dev/null || echo "" > /tmp/datainfo.properties
chmod 666 /tmp/datainfo.properties

# Extract DB state for the target user
echo "Extracting database state..."
MRIVERA_PASSWD_EPOCH=$(oc_query "SELECT EXTRACT(EPOCH FROM passwd_timestamp) FROM user_account WHERE user_name = 'mrivera'" 2>/dev/null | cut -d'.' -f1)
if [ -z "$MRIVERA_PASSWD_EPOCH" ]; then
    MRIVERA_PASSWD_EPOCH=0
fi
CURRENT_EPOCH=$(date +%s)

# Extract container restart evidence
INITIAL_START_AT=$(cat /tmp/container_start_time.txt 2>/dev/null || echo "unknown")
FINAL_START_AT=$(docker inspect -f '{{.State.StartedAt}}' oc-app 2>/dev/null || echo "unknown2")

# Build the result JSON
TEMP_JSON=$(mktemp)
cat > "$TEMP_JSON" << EOF
{
    "app_healthy": $APP_HEALTHY,
    "http_code": "$HTTP_CODE",
    "mrivera_passwd_epoch": $MRIVERA_PASSWD_EPOCH,
    "current_epoch": $CURRENT_EPOCH,
    "initial_start_at": "$INITIAL_START_AT",
    "final_start_at": "$FINAL_START_AT"
}
EOF

# Move JSON to final location securely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result data saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="