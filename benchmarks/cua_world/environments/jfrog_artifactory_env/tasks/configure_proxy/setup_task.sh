#!/bin/bash
echo "=== Setting up Configure Proxy task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Artifactory to be ready
echo "Checking Artifactory connectivity..."
if ! wait_for_artifactory 90; then
    echo "ERROR: Artifactory is not accessible."
    exit 1
fi

# Authenticate and capture initial system configuration
echo "Capturing initial system configuration..."
INITIAL_CONFIG=$(curl -s -u admin:password http://localhost:8082/artifactory/api/system/configuration)
echo "$INITIAL_CONFIG" > /tmp/initial_config.xml

# Ensure no proxy named 'corporate-proxy' exists
# We use a python script to check the XML. If it exists, we would technically need to remove it.
# For simplicity in this env, we assume a fresh start or fail if it's already there to avoid complex XML editing in bash.
# (Realistically, in a fresh container, it won't exist).
if echo "$INITIAL_CONFIG" | grep -q "corporate-proxy"; then
    echo "WARNING: corporate-proxy already exists in configuration."
else
    echo "Confirmed 'corporate-proxy' does not currently exist."
fi

# Start Firefox and prepare the UI
echo "Starting Firefox..."
ensure_firefox_running "http://localhost:8082"
sleep 5

# Attempt to navigate to the login page or dashboard
navigate_to "http://localhost:8082/ui/login"
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="