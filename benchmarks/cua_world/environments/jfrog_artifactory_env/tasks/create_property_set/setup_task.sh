#!/bin/bash
# Setup for: create_property_set task
set -e

echo "=== Setting up create_property_set task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure Artifactory is accessible
echo "Checking Artifactory connectivity..."
if ! wait_for_artifactory 90; then
    echo "ERROR: Artifactory is not accessible. Cannot proceed."
    exit 1
fi

# Ensure Firefox is running
ensure_firefox_running "http://localhost:8082"
sleep 5

# Capture initial configuration state (to detect changes later)
# We fetch the full system config XML to check if the property set already exists (it shouldn't)
curl -s -u admin:password "http://localhost:8082/artifactory/api/system/configuration" > /tmp/initial_config.xml 2>/dev/null || true

# Check if 'build-info' already exists in initial config and warn/fail
if grep -q "<name>build-info</name>" /tmp/initial_config.xml; then
    echo "WARNING: 'build-info' property set already exists! Attempting to clean up..."
    # In a real scenario we might try to delete it, but XML editing via curl is complex.
    # We assume the environment starts clean.
fi

# Maximize Firefox for the agent
focus_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="