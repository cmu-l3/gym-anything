#!/bin/bash
set -e
echo "=== Setting up Docker Address Pool Exhaustion Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Helper for Docker waiting
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

# 1. Clean up any previous state
docker rm -f acme-prod acme-ci-test 2>/dev/null || true
docker network prune -f 2>/dev/null || true

# 2. Configure Docker Daemon with EXTREMELY restrictive pool
# This pool (192.168.200.0/24) with size 24 allows exactly ONE network.
echo "Configuring restrictive daemon.json..."
cat > /tmp/daemon.json <<EOF
{
  "features": { "buildkit": true },
  "log-driver": "json-file",
  "default-address-pools": [
    {
      "base": "192.168.200.0/24",
      "size": 24
    }
  ]
}
EOF
sudo mv /tmp/daemon.json /etc/docker/daemon.json
sudo systemctl restart docker

# Wait for Docker to come back
wait_for_docker

# 3. Create "Production" Project
echo "Creating Production stack..."
mkdir -p /home/ga/projects/acme-prod
cat > /home/ga/projects/acme-prod/docker-compose.yml <<EOF
services:
  prod-web:
    image: nginx:1.24-alpine
    container_name: acme-prod
    restart: always
    ports:
      - "8080:80"
EOF
chown -R ga:ga /home/ga/projects/acme-prod

# Start Production (Consumes the ONLY available network slot)
echo "Starting Production (consuming the only pool slot)..."
cd /home/ga/projects/acme-prod
# We use sudo/root context for setup reliability, but permissions are ga
sudo docker compose up -d

# 4. Create "Test" Project (will fail to start)
echo "Creating Test stack..."
mkdir -p /home/ga/projects/acme-ci-test
cat > /home/ga/projects/acme-ci-test/docker-compose.yml <<EOF
services:
  test-web:
    image: nginx:1.24-alpine
    container_name: acme-ci-test
    restart: always
    ports:
      - "8081:80"
EOF
chown -R ga:ga /home/ga/projects/acme-ci-test

# Verify failure (optional check for log)
echo "Verifying exhaustion (expecting failure)..."
if cd /home/ga/projects/acme-ci-test && sudo docker compose up -d 2>&1 | grep -i "could not find an available"; then
    echo "Setup Verified: Address pool exhaustion triggered successfully."
else
    echo "WARNING: Setup might not have triggered exhaustion correctly."
fi

# 5. Record Initial State
date +%s > /tmp/task_start_time.txt
# Save the restrictive config hash to prove change later
md5sum /etc/docker/daemon.json > /tmp/initial_daemon_hash.txt

# 6. Prepare User Environment
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# Launch terminal
su - ga -c "DISPLAY=:1 gnome-terminal --maximize -- bash -c 'cd ~/projects/acme-ci-test; echo \"TASK: Fix Docker Address Pool Exhaustion\"; echo; echo \"Current status:\"; echo \"  acme-prod: RUNNING\"; echo \"  acme-ci-test: FAILING to start\"; echo; echo \"Try: docker compose up\"; echo; exec bash'" > /tmp/terminal_launch.log 2>&1 &
sleep 2

# Take screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="