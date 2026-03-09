#!/bin/bash
echo "=== Exporting WAF Task Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

APP_DIR="/home/ga/legacy-app"
cd "$APP_DIR" || exit 1

# 1. Functional Testing (HTTP Checks)
echo "Running traffic tests..."

# Wait a moment for services to stabilize if agent just restarted them
sleep 5

# Test 1: Legitimate Traffic (Should be 200)
# Use a retry loop as containers might be starting up
LEGIT_STATUS="000"
for i in {1..5}; do
    LEGIT_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/?q=Alice")
    if [ "$LEGIT_STATUS" != "000" ]; then break; fi
    sleep 2
done

# Test 2: SQL Injection (Should be 403 if WAF is working, 200 if vulnerable)
SQLI_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/?q='%20OR%201=1--")

# Test 3: XSS (Should be 403 if WAF is working)
XSS_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/?q=<script>alert(1)</script>")

echo "Traffic Results: Legit=$LEGIT_STATUS, SQLi=$SQLI_STATUS, XSS=$XSS_STATUS"

# 2. Architecture Inspection (Docker State)
echo "Inspecting Docker state..."

# Get compose project info
COMPOSE_SERVICES=$(docker compose ps --format '{{.Service}}' 2>/dev/null)

# Check if 'app' container exposes ports to host
# We look for "0.0.0.0:8080" or similar mapped to the app container
APP_CONTAINER_ID=$(docker compose ps -q app 2>/dev/null)
APP_HAS_DIRECT_PORTS="false"

if [ -n "$APP_CONTAINER_ID" ]; then
    PORT_MAP=$(docker inspect "$APP_CONTAINER_ID" --format='{{json .NetworkSettings.Ports}}')
    # If Ports is not "null" and contains "8080", it's likely still mapped
    if echo "$PORT_MAP" | grep -q "8080"; then
        APP_HAS_DIRECT_PORTS="true"
    fi
fi

# Check if WAF container exists and is running
WAF_RUNNING="false"
WAF_CONTAINER_IMAGE=""
# We don't know the service name the agent chose, so we look for the image
for container in $(docker compose ps -q 2>/dev/null); do
    IMG=$(docker inspect "$container" --format='{{.Config.Image}}')
    if [[ "$IMG" == *"modsecurity"* ]]; then
        WAF_RUNNING="true"
        WAF_CONTAINER_IMAGE="$IMG"
        break
    fi
done

# 3. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "legit_status": "$LEGIT_STATUS",
    "sqli_status": "$SQLI_STATUS",
    "xss_status": "$XSS_STATUS",
    "app_has_direct_ports": $APP_HAS_DIRECT_PORTS,
    "waf_running": $WAF_RUNNING,
    "waf_image": "$WAF_CONTAINER_IMAGE",
    "compose_services": "$(echo $COMPOSE_SERVICES | tr '\n' ' ')",
    "timestamp": $(date +%s)
}
EOF

# Save result
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="