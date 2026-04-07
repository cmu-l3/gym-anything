#!/bin/bash
set -e
echo "=== Setting up Docker Network Segmentation Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Fallback for wait_for_docker if utils not sourced
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

# Cleanup previous runs
docker compose -f /home/ga/projects/acme-platform/docker-compose.yml down 2>/dev/null || true
docker rm -f acme-proxy acme-api acme-users acme-orders acme-db acme-cache 2>/dev/null || true
docker network rm acme-flat dmz-net app-net data-net 2>/dev/null || true

# Create project directory
PROJECT_DIR="/home/ga/projects/acme-platform"
mkdir -p "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR/nginx"

# Create Nginx Config
cat > "$PROJECT_DIR/nginx/default.conf" << 'EOF'
server {
    listen 80;
    server_name localhost;

    location / {
        proxy_pass http://acme-api:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
EOF

# Create Docker Compose file (Flat Network Topology)
cat > "$PROJECT_DIR/docker-compose.yml" << 'EOF'
version: '3.8'

services:
  acme-proxy:
    image: nginx:1.24-alpine
    container_name: acme-proxy
    ports:
      - "8080:80"
    volumes:
      - ./nginx/default.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - acme-api
    networks:
      - acme-flat

  acme-api:
    image: python:3.11-slim
    container_name: acme-api
    command: python -m http.server 5000
    networks:
      - acme-flat

  acme-users:
    image: node:20-slim
    container_name: acme-users
    # Simple mock server
    command: node -e 'require("http").createServer((req,res)=>{res.writeHead(200);res.end("users")}).listen(3000)'
    networks:
      - acme-flat

  acme-orders:
    image: python:3.11-slim
    container_name: acme-orders
    command: python -m http.server 5001
    networks:
      - acme-flat

  acme-db:
    image: postgres:14
    container_name: acme-db
    environment:
      POSTGRES_PASSWORD: password
      POSTGRES_DB: acme_data
    networks:
      - acme-flat

  acme-cache:
    image: redis:7-alpine
    container_name: acme-cache
    networks:
      - acme-flat

networks:
  acme-flat:
    driver: bridge
EOF

chown -R ga:ga "$PROJECT_DIR"

# Start the initial state
echo "Starting initial flat-network environment..."
cd "$PROJECT_DIR"
# Run as ga user to ensure permissions are correct
su - ga -c "docker compose up -d"

# Wait for services
echo "Waiting for services to stabilize..."
sleep 10

# Verify start
if [ "$(docker ps -q | wc -l)" -lt 6 ]; then
    echo "ERROR: Not all containers started."
    docker ps -a
    docker logs acme-proxy
    exit 1
fi

# Record initial network state for reference
docker network inspect acme-flat > /tmp/initial_network_state.json

# Timestamp
date +%s > /tmp/task_start_time.txt

# Create Desktop
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# Open terminal
su - ga -c "DISPLAY=:1 gnome-terminal --maximize -- bash -c 'cd ~/projects/acme-platform && echo \"Current topology: ALL services on acme-flat\"; echo \"Task: Segment into dmz-net, app-net, and data-net\"; echo; ls -la; exec bash'" > /tmp/terminal.log 2>&1 &
sleep 2

# Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="