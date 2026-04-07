#!/bin/bash
set -e
echo "=== Setting up Docker Live Ops Triage Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Wait for Docker daemon
if ! type wait_for_docker &>/dev/null; then
    wait_for_docker() {
        for i in {1..60}; do
            if docker info > /dev/null 2>&1; then return 0; fi
            sleep 2
        done; return 1
    }
fi
wait_for_docker

# 1. Clean up previous state
echo "Cleaning up..."
docker rm -f acme-web acme-db acme-lb 2>/dev/null || true
docker network rm backend-net admin-net 2>/dev/null || true
rm -rf /home/ga/live_ops_config

# 2. Create Networks
echo "Creating networks..."
docker network create backend-net
docker network create admin-net

# 3. Setup Configs for Nginx (simulating the 'new' config placement)
mkdir -p /home/ga/live_ops_config
cat > /home/ga/live_ops_config/nginx_old.conf <<EOF
events { worker_connections 1024; }
http { 
    server { 
        listen 80; 
        location / { return 200 "Old Config"; } 
    } 
}
EOF

cat > /home/ga/live_ops_config/nginx_new.conf <<EOF
events { worker_connections 1024; }
http { 
    server { 
        listen 80; 
        location / { return 200 "New Config Loaded"; } 
    } 
}
EOF

# Initialize the bind mount source with OLD config first
cp /home/ga/live_ops_config/nginx_old.conf /home/ga/live_ops_config/nginx.conf

# 4. Start Containers
echo "Starting containers..."

# acme-web: Constrained resources (Python image)
# Using python image just to run a dummy process
docker run -d \
    --name acme-web \
    --memory="64m" \
    --cpus="0.1" \
    --network backend-net \
    python:3.11-slim \
    python3 -c "import time; print('Web running'); time.sleep(3600)"

# acme-db: Isolated network
docker run -d \
    --name acme-db \
    --network backend-net \
    postgres:14 \
    postgres -c "log_connections=on"

# acme-lb: Nginx with bind mount
docker run -d \
    --name acme-lb \
    --network backend-net \
    -v /home/ga/live_ops_config/nginx.conf:/etc/nginx/nginx.conf:ro \
    nginx:1.24-alpine

# 5. Simulate the "file updated but not reloaded" state
# We overwrite the file on the host. Since it's a bind mount, the container sees the new file immediately.
# But Nginx process has already started with the old file content in memory.
sleep 2
cp /home/ga/live_ops_config/nginx_new.conf /home/ga/live_ops_config/nginx.conf
echo "Updated nginx.conf on host (waiting for reload signal)"

# 6. Record Initial State (Start Times for Uptime Verification)
# We record the exact StartedAt timestamp. If this changes, it means a restart happened.
WEB_START=$(docker inspect acme-web --format '{{.State.StartedAt}}')
DB_START=$(docker inspect acme-db --format '{{.State.StartedAt}}')
LB_START=$(docker inspect acme-lb --format '{{.State.StartedAt}}')

cat > /tmp/initial_state.json <<EOF
{
    "web_start": "$WEB_START",
    "db_start": "$DB_START",
    "lb_start": "$LB_START",
    "task_start_ts": $(date +%s)
}
EOF

# 7. User Environment Setup
mkdir -p /home/ga/Desktop
chown -R ga:ga /home/ga/live_ops_config
chown ga:ga /home/ga/Desktop

# Terminal
su - ga -c "DISPLAY=:1 gnome-terminal --maximize -- bash -c 'echo \"⚠️  LIVE INCIDENT RESPONSE ⚠️\"; echo; echo \"1. acme-web: Throttled (Increase Mem to 1GB, CPU to 2.0)\"; echo \"2. acme-db: Isolated (Connect to admin-net)\"; echo \"3. acme-lb: Stale Config (Reload nginx without restart)\"; echo; echo \"REMINDER: DO NOT RESTART CONTAINERS\"; exec bash'" > /dev/null 2>&1 &
sleep 2

# Initial Screenshot
if type take_screenshot &>/dev/null; then
    take_screenshot /tmp/task_initial.png
else
    DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true
fi

echo "=== Setup Complete ==="