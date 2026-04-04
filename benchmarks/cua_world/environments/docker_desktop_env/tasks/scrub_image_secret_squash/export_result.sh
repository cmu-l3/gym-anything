#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Initialize result variables
SAFE_IMAGE_EXISTS="false"
SECRET_FOUND="true"
METADATA_CORRECT="false"
APP_FUNCTIONAL="false"
LAYER_COUNT_REDUCED="false"
APP_RESPONSE=""

# 1. Check if safe image exists
if docker image inspect legacy-app:safe >/dev/null 2>&1; then
    SAFE_IMAGE_EXISTS="true"
    
    # 2. Check for secret in history (The Core Test)
    # We grep the binary stream of docker save. 
    # 'grep -a' is crucial for binary files. 'grep -q' for quiet exit code.
    if docker save legacy-app:safe | grep -a -q "AKIA_TEST_SECRET_DO_NOT_USE"; then
        SECRET_FOUND="true"
        echo "FAIL: Secret found in safe image layers."
    else
        SECRET_FOUND="false"
        echo "PASS: Secret NOT found in safe image."
    fi

    # 3. Check Metadata (ENV, CMD, ExposedPorts)
    # We use python to parse the JSON inspect output carefully
    METADATA_CHECK=$(python3 -c "
import sys, json, subprocess
try:
    cmd = ['docker', 'inspect', 'legacy-app:safe']
    res = subprocess.check_output(cmd)
    data = json.loads(res)[0]
    config = data.get('Config', {})
    
    env_ok = 'APP_COLOR=blue' in config.get('Env', [])
    cmd_ok = config.get('Cmd') == ['python', 'app.py']
    port_ok = '5000/tcp' in config.get('ExposedPorts', {})
    
    if env_ok and cmd_ok and port_ok:
        print('true')
    else:
        print('false')
except:
    print('false')
")
    if [ "$METADATA_CHECK" == "true" ]; then
        METADATA_CORRECT="true"
    fi

    # 4. Functional Test
    TEST_CONTAINER_NAME="verifier-test-container"
    docker rm -f "$TEST_CONTAINER_NAME" >/dev/null 2>&1 || true
    
    # Run container mapping 5000->5050
    docker run -d --name "$TEST_CONTAINER_NAME" -p 5050:5000 legacy-app:safe
    
    # Wait for startup
    sleep 3
    
    # Test endpoint
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:5050)
    CONTENT=$(curl -s http://localhost:5050)
    
    if [ "$HTTP_CODE" == "200" ] && [[ "$CONTENT" == *"Color: blue"* ]]; then
        APP_FUNCTIONAL="true"
        APP_RESPONSE="OK"
    else
        APP_RESPONSE="FAIL: HTTP $HTTP_CODE - $CONTENT"
    fi
    
    # Clean up test container
    docker rm -f "$TEST_CONTAINER_NAME" >/dev/null 2>&1
else
    echo "Image legacy-app:safe not found."
fi

# Create result JSON
cat > /tmp/task_result.json << EOF
{
    "safe_image_exists": $SAFE_IMAGE_EXISTS,
    "secret_found_in_history": $SECRET_FOUND,
    "metadata_correct": $METADATA_CORRECT,
    "app_functional": $APP_FUNCTIONAL,
    "app_response": "$(json_escape "$APP_RESPONSE")",
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="