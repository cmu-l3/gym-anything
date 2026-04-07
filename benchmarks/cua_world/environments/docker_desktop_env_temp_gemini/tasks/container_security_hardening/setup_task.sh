#!/bin/bash
echo "=== Setting up container_security_hardening ==="

source /workspace/scripts/task_utils.sh

if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type wait_for_docker_daemon &>/dev/null; then
    wait_for_docker_daemon() {
        local timeout="${1:-60}"
        local i=0
        while [ $i -lt $timeout ]; do
            timeout 5 docker info >/dev/null 2>&1 && return 0
            sleep 2; i=$((i+2))
        done
        return 1
    }
fi

wait_for_docker_daemon 60

APP_DIR="/home/ga/insecure-app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR"

# --- Simple but real nginx-based web application ---
cat > "$APP_DIR/index.html" << 'EOF'
<!DOCTYPE html>
<html>
<head><title>Internal Dashboard</title></head>
<body>
<h1>Company Internal Dashboard</h1>
<p>Status: <strong>Running</strong></p>
<p>Version: 2.1.0</p>
</body>
</html>
EOF

cat > "$APP_DIR/nginx.conf" << 'EOF'
events { worker_processes 1; }
http {
    server {
        listen 80;
        root /usr/share/nginx/html;
        index index.html;
        location /health {
            return 200 '{"status":"ok"}';
            add_header Content-Type application/json;
        }
    }
}
EOF

# --- INSECURE Dockerfile (4 violations) ---
cat > "$APP_DIR/Dockerfile" << 'EOF'
# INSECURE Dockerfile - contains multiple CIS Docker Benchmark violations
FROM nginx:1.24

# Copy application files
COPY nginx.conf /etc/nginx/nginx.conf
COPY index.html /usr/share/nginx/html/index.html

# Running as root (no USER directive) — Violation #1
# No resource limits (to be set in compose) — Violation #4

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
EOF

# --- INSECURE docker-compose.yml (adds violations #2, #3, #4) ---
cat > "$APP_DIR/docker-compose.yml" << 'EOF'
services:
  web:
    build: .
    image: secure-web:insecure
    container_name: insecure-web
    ports:
      - "8090:80"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    privileged: true
    restart: unless-stopped
EOF

# Note: 4 security violations:
# 1. Dockerfile has no USER directive (runs as root, UID 0)
# 2. docker-compose.yml mounts /var/run/docker.sock (container escape risk)
# 3. docker-compose.yml has privileged: true (full host access)
# 4. No mem_limit or cpus resource constraints

# Stop any previous insecure container
docker stop insecure-web 2>/dev/null || true
docker rm insecure-web 2>/dev/null || true
docker rmi secure-web:insecure secure-web:hardened 2>/dev/null || true

# Build and start the insecure container
echo "Building insecure image..."
cd "$APP_DIR"
docker build -t secure-web:insecure . 2>&1 | tail -3

echo "Starting insecure container..."
docker compose up -d 2>&1 | tail -5

# Wait for it to be running
sleep 3

# Verify it's running
if docker ps --format "{{.Names}}" | grep -q "insecure-web"; then
    echo "Insecure container running: $(docker inspect insecure-web --format='User={{.Config.User}} Privileged={{.HostConfig.Privileged}}')"
else
    echo "WARNING: insecure-web container not running"
fi

# Record baseline
DOCKER_INSPECT=$(docker inspect insecure-web 2>/dev/null || echo "{}")
echo "$DOCKER_INSPECT" > /tmp/initial_insecure_inspect.json

# Record Dockerfile mtime
DOCKERFILE_MTIME=$(stat -c %Y "$APP_DIR/Dockerfile" 2>/dev/null || echo "0")
COMPOSE_MTIME=$(stat -c %Y "$APP_DIR/docker-compose.yml" 2>/dev/null || echo "0")
echo "$DOCKERFILE_MTIME" > /tmp/initial_dockerfile_mtime
echo "$COMPOSE_MTIME" > /tmp/initial_compose_mtime

date +%s > /tmp/task_start_timestamp

chown -R ga:ga "$APP_DIR"
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Insecure container running at http://localhost:8090"
echo "4 security violations present — agent must discover and fix all"
