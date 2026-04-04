#!/bin/bash
set -e
echo "=== Setting up scale_jvb_horizontal task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# Ensure we start from a clean state (single JVB)
# Navigate to jitsi directory
cd /home/ga/jitsi

# Check if jvb2 already exists (from previous run) and remove it
if docker ps -a | grep -q "jitsi-jvb2"; then
    echo "Cleaning up previous jvb2 container..."
    docker rm -f jitsi-jvb2 || true
fi

# Reset docker-compose.yml to original state if needed
# (Assuming the original is safe, but strictly we should ensure it has only 1 jvb)
# For this task, we assume the environment starts clean or we trust the user not to have messed it up yet.
# To be safe, we can check for 'jvb2' in the file and error out or reset.
if grep -q "jvb2:" docker-compose.yml; then
    echo "Resetting docker-compose.yml..."
    cp /workspace/config/docker-compose.yml /home/ga/jitsi/docker-compose.yml
fi

# Ensure Jitsi is running with the standard set of containers
echo "Ensuring Jitsi Meet is running..."
$DOCKER_COMPOSE up -d web prosody jicofo jvb

# Wait for health
sleep 5

# Record initial container count
INITIAL_COUNT=$(docker ps --format "{{.Names}}" | grep -c "jitsi-")
echo "$INITIAL_COUNT" > /tmp/initial_count.txt

# Start Firefox on the landing page so the agent sees the app is live
restart_firefox "http://localhost:8080" 5
maximize_firefox

# Take screenshot of initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="