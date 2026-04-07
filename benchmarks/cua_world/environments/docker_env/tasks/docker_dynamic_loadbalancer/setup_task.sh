#!/bin/bash
set -e
echo "=== Setting up Docker Dynamic Load Balancer Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Wait for Docker to be ready
wait_for_docker

# Project setup
PROJECT_DIR="/home/ga/projects/acme-proxy"
mkdir -p "$PROJECT_DIR/nginx"
mkdir -p "$PROJECT_DIR/backend"

# Create Backend App (Flask)
cat > "$PROJECT_DIR/backend/app.py" << 'EOF'
from flask import Flask, jsonify
import socket
import os

app = Flask(__name__)

@app.route('/')
def home():
    return jsonify({
        "service": "payment-processor",
        "hostname": socket.gethostname(),
        "ip": socket.gethostbyname(socket.gethostname()),
        "status": "active"
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

cat > "$PROJECT_DIR/backend/Dockerfile" << 'EOF'
FROM python:3.11-slim
RUN pip install flask
WORKDIR /app
COPY app.py .
CMD ["python", "app.py"]
EOF

# Create Nginx Config Template
cat > "$PROJECT_DIR/nginx/nginx.conf.template" << 'EOF'
events {}

http {
    upstream backend_servers {
        # AUTOMATICALLY GENERATED - DO NOT EDIT MANUALLY
        # {{UPSTREAMS}}
        server 127.0.0.1:5000 down; # Placeholder to prevent startup error
    }

    server {
        listen 80;
        
        location / {
            proxy_pass http://backend_servers;
            proxy_connect_timeout 2s;
        }
    }
}
EOF

# Initial broken config (so Nginx starts but fails routing)
cp "$PROJECT_DIR/nginx/nginx.conf.template" "$PROJECT_DIR/nginx/nginx.conf"

# Create Docker Compose
cat > "$PROJECT_DIR/docker-compose.yml" << 'EOF'
version: '3'
services:
  proxy:
    image: nginx:1.24-alpine
    container_name: acme-proxy
    ports:
      - "8080:80"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf
    depends_on:
      - backend

  backend:
    build: ./backend
    deploy:
      replicas: 2
    labels:
      role: "backend"
      env: "production"

networks:
  default:
    name: acme-net
EOF

# Set permissions
chown -R ga:ga "$PROJECT_DIR"

# Build and Start
echo "Building and starting stack..."
cd "$PROJECT_DIR"
# Run as ga user to ensure images are owned correctly if feasible, 
# but docker socket is usually root group. We run as root here for setup reliability.
docker compose up -d --build

# Wait for Nginx container to be running
for i in {1..30}; do
    if [ "$(docker inspect -f '{{.State.Running}}' acme-proxy 2>/dev/null)" == "true" ]; then
        echo "Nginx proxy is running."
        break
    fi
    sleep 1
done

# Record start time
date +%s > /tmp/task_start_timestamp

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Project Directory: $PROJECT_DIR"
echo "Stack running: acme-proxy (port 8080), acme-backend (2 replicas)"