#!/bin/bash
# Setup script for docker_key_recovery task
set -e
echo "=== Setting up Docker Key Recovery Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Fallback wait_for_docker if utils not sourced
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

# Cleanup any previous runs
echo "Cleaning up previous containers..."
docker rm -f keyvault-storage keyvault-cache keyvault-proxy keyvault-worker keyvault-scheduler 2>/dev/null || true
docker volume rm -f scheduler-data 2>/dev/null || true
rm -f /home/ga/Desktop/recovered_key.txt 2>/dev/null || true
rm -f /home/ga/Desktop/recovery_report.txt 2>/dev/null || true

# 1. keyvault-cache (Env Var)
# Fragment: c4d81f56
echo "Starting keyvault-cache..."
docker run -d --name keyvault-cache \
    -e "DB_HOST=pg-primary" \
    -e "REDIS_URL=redis://cache:6379" \
    -e "CACHE_SESSION_TOKEN=c4d81f56" \
    -e "LOG_LEVEL=debug" \
    -e "MAX_RETRIES=5" \
    alpine:3.18 sh -c 'while true; do sleep 3600; done'

# 2. keyvault-proxy (Logs)
# Fragment: e9027a4d
echo "Starting keyvault-proxy..."
docker run -d --name keyvault-proxy \
    alpine:3.18 sh -c '
    echo "Starting proxy service v2.4.1..."
    while true; do 
        echo "[INFO] $(date -Iseconds) - Handling request ID $(od -An -N2 -i /dev/urandom | tr -d " ")"
        sleep 2
        echo "RECOVERY_FRAGMENT:e9027a4d"
        sleep 1
        echo "[INFO] $(date -Iseconds) - Health check passed"
        sleep 5
    done'

# 3. keyvault-scheduler (Volume)
# Fragment: a2f4d709
echo "Starting keyvault-scheduler..."
docker volume create scheduler-data
# Pre-populate volume
docker run --rm -v scheduler-data:/data alpine:3.18 sh -c 'echo "a2f4d709" > /data/fragment.key'
# Run container mounting it
docker run -d --name keyvault-scheduler \
    -v scheduler-data:/data \
    alpine:3.18 sh -c 'while true; do sleep 3600; done'

# 4. keyvault-storage (Label)
# Fragment: 7f3a9b2e
echo "Starting keyvault-storage..."
docker run -d --name keyvault-storage \
    --label "version=1.4.2" \
    --label "maintainer=sysadmin@acmecorp.com" \
    --label "com.acme.recovery.fragment=7f3a9b2e" \
    --label "tier=backend" \
    alpine:3.18 sh -c 'while true; do sleep 3600; done'

# 5. keyvault-worker (File inside)
# Fragment: 5b6c8e31
echo "Starting keyvault-worker..."
docker run -d --name keyvault-worker \
    alpine:3.18 sh -c '
    mkdir -p /var/run/secrets
    echo "5b6c8e31" > /var/run/secrets/fragment.key
    chmod 600 /var/run/secrets/fragment.key
    while true; do sleep 3600; done'

# Ensure Desktop exists
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Wait for containers to stabilize
sleep 5

# Open terminal for agent
su - ga -c "DISPLAY=:1 gnome-terminal --maximize -- bash -c 'echo \"Docker Key Recovery Task\"; echo \"------------------------\"; echo \"Goal: Find hidden key fragments in 5 containers and assemble the key.\"; echo \"      See task description for details.\"; echo; docker ps --format \"table {{.Names}}\t{{.Status}}\"; echo; exec bash'" > /tmp/recovery_terminal.log 2>&1 &

# Take initial screenshot
take_screenshot /tmp/task_start.png 2>/dev/null || true

echo "=== Setup Complete ==="