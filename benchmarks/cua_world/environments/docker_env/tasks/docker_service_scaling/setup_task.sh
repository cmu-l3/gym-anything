#!/bin/bash
# Setup script for docker_service_scaling task
set -e

echo "=== Setting up Docker Service Scaling Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type wait_for_docker &>/dev/null; then
    wait_for_docker() {
        for i in {1..60}; do
            if docker info > /dev/null 2>&1; then return 0; fi
            sleep 2
        done; return 1
    }
fi
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

wait_for_docker

# Cleanup previous
docker compose -f /home/ga/projects/acme-storefront/docker-compose.yml down 2>/dev/null || true
docker rm -f $(docker ps -a -q --filter "name=acme-") 2>/dev/null || true

# Create Project Directory
PROJECT_DIR="/home/ga/projects/acme-storefront"
mkdir -p "$PROJECT_DIR/api"
mkdir -p "$PROJECT_DIR/nginx"

# 1. Create Python API App
cat > "$PROJECT_DIR/api/app.py" << 'EOF'
from flask import Flask, jsonify
import socket
import os

app = Flask(__name__)

@app.route('/api/products')
def products():
    # Simulate DB query
    return jsonify([
        {"id": 1, "name": "Acme Widget", "price": 19.99},
        {"id": 2, "name": "Acme Gadget", "price": 49.99},
        {"id": 3, "name": "Acme Gizmo", "price": 9.99}
    ]), 200, {'X-Served-By': socket.gethostname()}

@app.route('/api/health')
def health():
    return jsonify({
        "status": "healthy", 
        "hostname": socket.gethostname(),
        "service": "acme-api"
    }), 200, {'X-Served-By': socket.gethostname()}

if __name__ == "__main__":
    app.run(host='0.0.0.0', port=5000)
EOF

cat > "$PROJECT_DIR/api/requirements.txt" << 'EOF'
flask==2.3.3
EOF

cat > "$PROJECT_DIR/api/Dockerfile" << 'EOF'
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
CMD ["python", "app.py"]
EOF

# 2. Create Initial Nginx Config (Naive configuration)
cat > "$PROJECT_DIR/nginx/nginx.conf" << 'EOF'
events {
    worker_connections 1024;
}

http {
    server {
        listen 80;
        
        location / {
            # Simple proxy pass - works for single instance, 
            # but problematic for scaling if not configured with resolver/upstream
            proxy_pass http://api:5000;
            
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            add_header X-Load-Balancer "Acme-Nginx";
        }
    }
}
EOF

# 3. Create Docker Compose File (Single Replica)
cat > "$PROJECT_DIR/docker-compose.yml" << 'EOF'
services:
  db:
    image: postgres:14
    environment:
      POSTGRES_PASSWORD: password
      POSTGRES_DB: products
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      timeout: 5s
      retries: 5

  cache:
    image: redis:7-alpine
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 3s
      retries: 5

  api:
    build: ./api
    image: acme-api:latest
    environment:
      DATABASE_URL: postgres://postgres:password@db:5432/products
      REDIS_URL: redis://cache:6379
    depends_on:
      db:
        condition: service_healthy
      cache:
        condition: service_healthy
    # Start with 1 replica - agent must change this to 3
    deploy:
      replicas: 1

  nginx:
    image: nginx:1.24-alpine
    ports:
      - "8080:80"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
    depends_on:
      - api
EOF

# Set permissions
chown -R ga:ga "$PROJECT_DIR"

# Start the stack
echo "Starting initial stack..."
cd "$PROJECT_DIR"
# Use DOCKER_BUILDKIT=1 to ensure clean build
export DOCKER_BUILDKIT=1
sudo -u ga docker compose up -d --build

# Wait for stack to be ready
echo "Waiting for API to be ready..."
for i in {1..30}; do
    if curl -s http://localhost:8080/api/health | grep -q "healthy"; then
        echo "API is up and running."
        break
    fi
    sleep 2
done

# Record initial state
date +%s > /tmp/task_start_time
INITIAL_REPLICAS=$(docker ps --format '{{.Names}}' | grep "api" | wc -l)
echo "$INITIAL_REPLICAS" > /tmp/initial_replicas.txt

# Create Desktop dir
sudo -u ga mkdir -p /home/ga/Desktop

# Launch terminal
su - ga -c "DISPLAY=:1 gnome-terminal --maximize -- bash -c 'cd ~/projects/acme-storefront && echo \"Docker Service Scaling Task\"; echo \"Current Status:\"; docker compose ps; echo; echo \"Task: Scale API to 3 replicas and configure Nginx load balancing.\"; exec bash'" > /tmp/terminal.log 2>&1 &
sleep 5

take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="