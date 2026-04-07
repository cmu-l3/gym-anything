#!/bin/bash
# Setup script for docker_debug_distroless
# Simulates a distroless container by stripping an Alpine image at runtime
# and hiding configuration in process memory.

set -e
echo "=== Setting up Distroless Debug Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type wait_for_docker &>/dev/null; then
    wait_for_docker() {
        for i in {1..60}; do
            if docker info > /dev/null 2>&1; then return 0; fi
            sleep 2
        done; return 1
    }
fi

wait_for_docker

# 1. Generate random configuration
# Port between 8000 and 9000
RANDOM_PORT=$((8000 + RANDOM % 1000))
# Random Auth Token
RANDOM_TOKEN=$(date +%s | sha256sum | base64 | head -c 32)

echo "Configuration (Hidden):"
echo "  Port: $RANDOM_PORT"
echo "  Token: $RANDOM_TOKEN"

# 2. Save ground truth to a location secure from the agent (root-owned)
# We use /root/ because the agent runs as 'ga' and cannot read it.
cat > /root/blackbox_ground_truth.json <<EOF
{
  "port": $RANDOM_PORT,
  "auth_token": "$RANDOM_TOKEN"
}
EOF
chmod 600 /root/blackbox_ground_truth.json

# 3. Create the 'Distroless' Simulation
# We create a startup script that sets the env var, starts the app,
# and THEN deletes the shell and itself, making it impossible to exec later.
# We explicitly do NOT use ENV in Dockerfile/run command so 'docker inspect' doesn't show it.

WORKDIR="/root/distroless_build"
mkdir -p "$WORKDIR"

cat > "$WORKDIR/entrypoint.sh" <<EOF
#!/bin/sh
export AUTH_TOKEN="$RANDOM_TOKEN"
echo "Starting Blackbox Service..."

# Delete shells and common tools to simulate distroless
rm -f /bin/sh /bin/ash /usr/bin/wc /usr/bin/env /bin/cat /bin/ls

# Start a listener (netcat) on the random port
# exec replaces the shell process, keeping PID 1
# We use a trick to keep the port open and respond with nothing
exec nc -lk -p $RANDOM_PORT -e /dev/null
EOF

chmod +x "$WORKDIR/entrypoint.sh"

# 4. Clean up any previous container
docker rm -f acme-blackbox 2>/dev/null || true

# 5. Start the container
# We mount the entrypoint, run it, but don't persist it in the image config
echo "Starting acme-blackbox..."
docker run -d \
  --name acme-blackbox \
  --restart always \
  -v "$WORKDIR/entrypoint.sh":/entrypoint.sh \
  alpine:3.18 \
  /entrypoint.sh

# 6. Verify it's running and hardened
sleep 5
if ! docker ps | grep -q acme-blackbox; then
    echo "ERROR: acme-blackbox failed to start"
    docker logs acme-blackbox
    exit 1
fi

# Verify 'docker exec' fails (it should, as /bin/sh is gone)
if docker exec acme-blackbox sh -c "echo test" 2>/dev/null; then
    echo "WARNING: Simulation failed - shell still exists!"
else
    echo "Verification: 'docker exec' correctly failed (container is hardened)."
fi

# 7. Clean up host artifacts so agent can't find the token on disk
rm -rf "$WORKDIR"

# 8. User Environment Setup
date +%s > /tmp/task_start_timestamp
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# Open terminal for agent
su - ga -c "DISPLAY=:1 gnome-terminal --maximize -- bash -c 'echo \"=== Docker Distroless Debugging ===\"; echo \"Container acme-blackbox is running.\"; echo \"Problem: Cannot connect to service, need to find listening port and AUTH_TOKEN.\"; echo \"Constraint: Container has no shell (distroless). docker exec will fail.\"; echo \"Goal: Write report to ~/Desktop/blackbox_report.json\"; echo; exec bash'" > /tmp/task_terminal.log 2>&1 &

# Take evidence screenshot
take_screenshot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== Setup Complete ==="