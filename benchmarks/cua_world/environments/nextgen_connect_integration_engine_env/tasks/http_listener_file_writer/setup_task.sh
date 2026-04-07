#!/bin/bash
echo "=== Setting up HTTP Listener File Writer task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

source /workspace/scripts/task_utils.sh

# Wait for API to be ready before doing anything
echo "Waiting for NextGen Connect API..."
wait_for_api 120 || echo "WARNING: API may not be ready"

# Record initial channel count
INITIAL_COUNT=$(get_channel_count)
echo "$INITIAL_COUNT" > /tmp/initial_channel_count.txt
echo "Initial channel count: $INITIAL_COUNT"

# Record initial file count in output dir (should be 0 as we create it new)
echo "0" > /tmp/initial_file_count.txt

# Create output directory on host
echo "Creating output directory..."
mkdir -p /home/ga/output
# Ensure permissions allow the container user (likely root or restricted) to write
chmod 777 /home/ga/output
chown ga:ga /home/ga/output

# Recreate NextGen Connect container with bind mount for output directory
# This is critical so the File Writer inside the container can write to the host path agent sees
echo "Recreating NextGen Connect container with output volume mount..."
docker stop nextgen-connect 2>/dev/null || true
docker rm nextgen-connect 2>/dev/null || true

# Give Docker a moment to clean up
sleep 3

# Relaunch with -v /home/ga/output:/home/ga/output
docker run -d \
    --name nextgen-connect \
    --restart unless-stopped \
    --network nextgen-network \
    -p 8080:8080 \
    -p 8443:8443 \
    -p 6661:6661 \
    -p 6662:6662 \
    -p 6663:6663 \
    -p 6664:6664 \
    -p 6665:6665 \
    -p 6666:6666 \
    -p 6667:6667 \
    -p 6668:6668 \
    -v /home/ga/output:/home/ga/output \
    -e DATABASE=postgres \
    -e DATABASE_URL=jdbc:postgresql://nextgen-postgres:5432/mirthdb \
    -e DATABASE_USERNAME=postgres \
    -e DATABASE_PASSWORD=postgres \
    -e KEYSTORE_STOREPASS=docker_storepass \
    -e KEYSTORE_KEYPASS=docker_keypass \
    nextgenhealthcare/connect:4.5.0

echo "Waiting for NextGen Connect to restart..."
wait_for_api 180 || echo "WARNING: API timeout after restart"

# Extra time for full initialization of internal services
sleep 15

# Verify API is accessible
VERSION=$(curl -sk -u admin:admin -H "X-Requested-With: OpenAPI" -H "Accept: text/plain" https://localhost:8443/api/server/version 2>/dev/null)
echo "NextGen Connect version: $VERSION"

# Verify port 6661 is NOT yet listening (no channel configured yet)
if nc -z localhost 6661 2>/dev/null; then
    echo "NOTE: Port 6661 is already open (unexpected, but proceeding)"
else
    echo "Port 6661 is not yet listening (expected)"
fi

# Verify bind mount works by listing it inside container
docker exec nextgen-connect ls -la /home/ga/output/ 2>/dev/null && echo "Bind mount verified" || echo "WARNING: Bind mount issue"

# Ensure Firefox is showing the landing page
pkill -f firefox 2>/dev/null || true
sleep 2
su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080' &" 2>/dev/null
sleep 5

# Maximize Firefox
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true

# Take screenshot of initial state
take_screenshot /tmp/task_initial_state.png

echo ""
echo "=== Task setup complete ==="
echo "API: https://localhost:8443/api"
echo "HTTP port 6661 mapped to container"
echo "Output directory: /home/ga/output/"