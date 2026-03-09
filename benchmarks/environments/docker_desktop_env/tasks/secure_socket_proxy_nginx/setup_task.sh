#!/bin/bash
set -e
echo "=== Setting up Secure Socket Proxy Task ==="

source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# Create project directory
PROJECT_DIR="/home/ga/Documents/docker-projects/monitor-stack"
mkdir -p "$PROJECT_DIR"
chown -R ga:ga "$PROJECT_DIR"

# Create the monitor script
cat > "$PROJECT_DIR/monitor.sh" << 'SCRIPT'
#!/bin/sh
# Simple Docker monitoring script
# Dependencies: curl, jq
set -e

# Install dependencies if missing (Alpine)
if ! command -v jq >/dev/null; then
    apk add --no-cache curl jq >/dev/null 2>&1
fi

echo "=== Docker Monitor Agent v1.0 ==="
echo "Target: ${DOCKER_HOST:-unix:///var/run/docker.sock}"

while true; do
    echo "Querying Docker API..."
    
    # Handle TCP vs Socket URL
    if echo "$DOCKER_HOST" | grep -q "tcp://"; then
        # Convert tcp://host:port to http://host:port for curl
        TARGET_URL=$(echo "$DOCKER_HOST" | sed 's/tcp:\/\//http:\/\//')
        RESPONSE=$(curl -s --connect-timeout 2 --max-time 5 "$TARGET_URL/containers/json") || true
    else
        TARGET_URL="http://localhost/containers/json"
        RESPONSE=$(curl -s --unix-socket /var/run/docker.sock "$TARGET_URL") || true
    fi

    if [ -n "$RESPONSE" ] && echo "$RESPONSE" | jq -e . >/dev/null 2>&1; then
        COUNT=$(echo "$RESPONSE" | jq 'length')
        echo "$(date): Successfully retrieved container count: $COUNT"
    else
        echo "$(date): ERROR - Failed to contact Docker API at $TARGET_URL"
        echo "Debug: Response was: $RESPONSE"
    fi
    
    sleep 10
done
SCRIPT
chmod +x "$PROJECT_DIR/monitor.sh"

# Create the INSECURE docker-compose.yml
cat > "$PROJECT_DIR/docker-compose.yml" << 'YAML'
services:
  monitor:
    image: alpine:latest
    container_name: monitor-agent
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock  # SECURITY RISK!
      - ./monitor.sh:/monitor.sh
    command: /monitor.sh
    restart: unless-stopped
YAML

# Fix permissions
chown -R ga:ga "$PROJECT_DIR"

# Ensure Docker Desktop is ready
wait_for_docker_daemon 60

# Start the initial insecure stack
echo "Starting initial insecure stack..."
cd "$PROJECT_DIR"
# Run as ga user to simulate real environment
su - ga -c "cd $PROJECT_DIR && docker compose up -d"

# Wait for container to be running
sleep 5
if docker ps | grep -q "monitor-agent"; then
    echo "Initial stack running."
else
    echo "WARNING: Initial stack failed to start."
fi

# Open VS Code or a terminal in the project directory to hint where to start
# We'll just open a terminal
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=$PROJECT_DIR &"
    sleep 2
fi

# Maximize Docker Desktop if running, else just ensure environment is ready
focus_docker_desktop || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="