#!/bin/bash
set -e

echo "=== Setting up Docker Remote Service Recovery Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Function to wait for Docker
if ! type wait_for_docker &>/dev/null; then
    wait_for_docker() {
        for i in {1..60}; do
            if docker info > /dev/null 2>&1; then return 0; fi
            sleep 2
        done
        return 1
    }
fi

wait_for_docker

# Record start time
date +%s > /tmp/task_start_time.txt

# 1. Clean up any previous runs
echo "Cleaning up previous resources..."
docker rm -f staging-node 2>/dev/null || true
docker network rm staging-net 2>/dev/null || true
# Clean up agent contexts if any (running as ga)
su - ga -c "docker context rm -f staging 2>/dev/null || true"

# 2. Create the network
echo "Creating staging network..."
docker network create staging-net

# 3. Connect the agent container to this network so it can resolve 'staging-node'
# We get the container ID of the current environment (hostname usually matches container ID in Docker)
AGENT_CONTAINER_ID=$(hostname)
echo "Connecting agent container ($AGENT_CONTAINER_ID) to staging-net..."
docker network connect staging-net "$AGENT_CONTAINER_ID" || true

# 4. Start the Remote Docker Host (DinD)
echo "Starting staging-node (DinD)..."
docker run -d \
    --name staging-node \
    --network staging-net \
    --privileged \
    docker:dind \
    dockerd --host=tcp://0.0.0.0:2375 --host=unix:///var/run/docker.sock --tls=false

# 5. Wait for the remote daemon to be ready
echo "Waiting for staging-node daemon..."
for i in {1..30}; do
    if docker run --rm --network staging-net docker:cli -H tcp://staging-node:2375 info >/dev/null 2>&1; then
        echo "Remote daemon is ready."
        break
    fi
    sleep 2
    if [ "$i" -eq 30 ]; then
        echo "Timeout waiting for staging-node."
        exit 1
    fi
done

# 6. Launch the BROKEN container on the remote host
# It crashes because UPSTREAM_TARGET is missing
echo "Deploying broken web-proxy to staging-node..."
docker run --rm --network staging-net docker:cli \
    -H tcp://staging-node:2375 \
    run -d \
    --name web-proxy \
    -p 8080:80 \
    --restart=no \
    nginx:alpine \
    /bin/sh -c 'if [ -z "$UPSTREAM_TARGET" ]; then echo "CRITICAL: UPSTREAM_TARGET environment variable is not set. Service cannot start."; exit 1; else echo "Starting proxy for $UPSTREAM_TARGET..."; exec nginx -g "daemon off;"; fi'

# 7. Open Terminal for the agent
# We use gnome-terminal to give the agent a place to work
if pgrep -f "gnome-terminal" > /dev/null; then
    pkill -f "gnome-terminal"
fi

su - ga -c "DISPLAY=:1 gnome-terminal --maximize -- bash -c 'echo \"=== INCIDENT ALERT ===\"; echo \"Service: web-proxy\"; echo \"Host: staging-node\"; echo \"Status: DOWN\"; echo \"SSH Access: DENIED\"; echo \"Docker API: tcp://staging-node:2375\"; echo; echo \"Diagnose and recover the service.\"; exec bash'" > /dev/null 2>&1 &

# 8. Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="