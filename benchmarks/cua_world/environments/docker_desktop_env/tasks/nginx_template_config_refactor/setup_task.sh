#!/bin/bash
set -e
echo "=== Setting up Nginx Template Refactor Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create project directory
PROJECT_DIR="/home/ga/proxy-refactor"
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR/nginx"

# Create dummy backend service (using traefik/whoami as a lightweight echo server)
# and the nginx proxy definition
cat > "$PROJECT_DIR/docker-compose.yml" << 'EOF'
services:
  backend:
    image: traefik/whoami:v1.10
    container_name: refactor-backend
    command: --port=8080
    networks:
      - app-net

  proxy:
    image: nginx:alpine
    container_name: refactor-proxy
    ports:
      - "80:80"
    volumes:
      - ./nginx/default.conf:/etc/nginx/conf.d/default.conf
    networks:
      - app-net
    depends_on:
      - backend

networks:
  app-net:
EOF

# Create the HARDCODED (and BROKEN) nginx config
# It points to localhost:8080, which is wrong inside the container
cat > "$PROJECT_DIR/nginx/default.conf" << 'EOF'
server {
    listen 80;
    server_name localhost;

    location / {
        # TODO: Refactor this to use ${BACKEND_URL}
        proxy_pass http://localhost:8080;
        
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
EOF

# Set permissions
chown -R ga:ga "$PROJECT_DIR"

# Wait for Docker daemon
wait_for_docker_daemon 60

# Pre-pull images to save time and ensure offline capability if needed
echo "Pre-pulling images..."
docker pull nginx:alpine >/dev/null 2>&1 || true
docker pull traefik/whoami:v1.10 >/dev/null 2>&1 || true

# Open a terminal or file explorer at the location (simulated focus)
# We ensure the directory exists and permissions are right.
ls -la "$PROJECT_DIR"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "Project located at: $PROJECT_DIR"
echo "Current status: Broken (proxy_pass points to localhost)"