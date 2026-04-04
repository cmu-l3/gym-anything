#!/bin/bash
# Setup script for secure_dind_socket_access task

echo "=== Setting up secure_dind_socket_access task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Docker Desktop is running
if ! docker_desktop_running; then
    echo "Starting Docker Desktop..."
    su - ga -c "DISPLAY=:1 XDG_RUNTIME_DIR=/run/user/1000 /opt/docker-desktop/bin/docker-desktop > /tmp/docker-desktop.log 2>&1 &"
    sleep 10
fi

# Wait for Docker daemon
wait_for_docker_daemon 60

# Project directory
PROJECT_DIR="/home/ga/build-agent"
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR"

# Create Dockerfile
# We use docker:cli-alpine as base, add a user 'agent'
cat > "$PROJECT_DIR/Dockerfile" << 'EOF'
FROM docker:cli
# Create a non-root user
RUN adduser -D -u 1000 agent
# Switch to non-root user
USER agent
EOF

# Create docker-compose.yml
# Intentionally broken: mounts socket but doesn't handle group permissions
cat > "$PROJECT_DIR/docker-compose.yml" << 'EOF'
services:
  agent:
    build: .
    container_name: build-agent
    # Explicitly set user to ensure it overrides any image default (though Dockerfile sets it too)
    user: agent
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    # Keep container running
    command: sh -c "while true; do sleep 3600; done"
EOF

chown -R ga:ga "$PROJECT_DIR"

# Clean up any previous container
docker rm -f build-agent 2>/dev/null || true

# Record initial socket permissions for verification
SOCKET_PERMS=$(stat -c %a /var/run/docker.sock 2>/dev/null || echo "000")
echo "$SOCKET_PERMS" > /tmp/initial_socket_perms

# Focus Docker Desktop
focus_docker_desktop

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo ""
echo "=== Task setup complete ==="
echo "Project created at: $PROJECT_DIR"
echo "Host Socket Permissions: $SOCKET_PERMS (Do not change this!)"
echo ""