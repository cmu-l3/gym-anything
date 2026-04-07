#!/bin/bash
echo "=== Exporting Dynamic Load Balancer Results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true
take_screenshot /tmp/task_end_screenshot.png

PROJECT_DIR="/home/ga/projects/acme-proxy"
SCRIPT_PATH="$PROJECT_DIR/sync_lb.py"
NGINX_CONF="$PROJECT_DIR/nginx/nginx.conf"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Initialize result variables
SCRIPT_EXISTS=0
SCRIPT_RUNS=0
PROBE_DETECTED=0
LABEL_FILTERING_LIKELY=0
NGINX_VALID=0
NGINX_RELOADED=0
TRAFFIC_FLOWING=0

# 1. Check script existence
if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_EXISTS=1
fi

# 2. Dynamic Discovery Verification
# We will spin up a NEW container that the agent has never seen.
# If the script is robust, it should pick this up.
echo "Starting verification probe container..."
PROBE_NAME="acme-verification-probe"
# Remove if exists from previous run
docker rm -f $PROBE_NAME 2>/dev/null || true

# Reuse the backend image built during setup
BACKEND_IMAGE=$(docker images --format "{{.Repository}}" | grep backend | head -n 1)
if [ -z "$BACKEND_IMAGE" ]; then BACKEND_IMAGE="python:3.11-slim"; fi

# Start probe with the correct label
docker run -d \
    --name $PROBE_NAME \
    --network acme-net \
    --label role=backend \
    --label verification=true \
    $BACKEND_IMAGE \
    python app.py > /dev/null

# Get probe IP
sleep 3
PROBE_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $PROBE_NAME)
echo "Probe container started at $PROBE_IP"

# 3. Run the agent's script
if [ "$SCRIPT_EXISTS" = "1" ]; then
    echo "Executing agent script..."
    # Run as ga user, assume dependencies are installed
    if sudo -u ga python3 "$SCRIPT_PATH" > /tmp/script_execution.log 2>&1; then
        SCRIPT_RUNS=1
    else
        echo "Script execution failed."
        cat /tmp/script_execution.log
    fi
fi

# 4. Analyze resulting config
if [ "$SCRIPT_RUNS" = "1" ]; then
    # Check if Probe IP is in config
    if grep -q "$PROBE_IP" "$NGINX_CONF"; then
        PROBE_DETECTED=1
    fi
    
    # Check for label filtering (Negative test)
    # Start a container WITHOUT the label and ensure it's NOT in the config
    docker run -d --name acme-noise --network acme-net nginx:alpine > /dev/null
    NOISE_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' acme-noise)
    
    # Run script again
    sudo -u ga python3 "$SCRIPT_PATH" > /dev/null 2>&1
    
    if ! grep -q "$NOISE_IP" "$NGINX_CONF"; then
        LABEL_FILTERING_LIKELY=1
    fi
    docker rm -f acme-noise > /dev/null
fi

# 5. Check Nginx Config Validity and Status
if docker exec acme-proxy nginx -t > /dev/null 2>&1; then
    NGINX_VALID=1
fi

# 6. Functional Traffic Test
# Curl the proxy. Since we have 3 backends (2 original + 1 probe), 
# repeated requests should hit all of them eventually if LB is working.
SUCCESS_COUNT=0
for i in {1..10}; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ]; then
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    fi
    sleep 0.2
done

if [ "$SUCCESS_COUNT" -gt 0 ]; then
    TRAFFIC_FLOWING=1
    # If traffic is flowing and config is valid, it implies reload happened 
    # (or was handled by the script)
    NGINX_RELOADED=1
fi

# Cleanup
docker rm -f $PROBE_NAME > /dev/null

# Export to JSON
cat > /tmp/lb_result.json <<EOF
{
    "task_start": $TASK_START,
    "script_exists": $SCRIPT_EXISTS,
    "script_runs_successfully": $SCRIPT_RUNS,
    "probe_detected": $PROBE_DETECTED,
    "label_filtering_verified": $LABEL_FILTERING_LIKELY,
    "nginx_config_valid": $NGINX_VALID,
    "traffic_flowing": $TRAFFIC_FLOWING,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result JSON:"
cat /tmp/lb_result.json
echo "=== Export Complete ==="