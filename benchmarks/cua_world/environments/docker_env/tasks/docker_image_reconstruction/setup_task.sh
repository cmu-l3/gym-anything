#!/bin/bash
# Setup script for docker_image_reconstruction task
# Creates source code and builds "production" images, then deletes the Dockerfiles.

set -e
echo "=== Setting up Docker Image Reconstruction Task ==="

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
docker rm -f acme-api-prod acme-cron-prod acme-gateway-prod 2>/dev/null || true
rm -rf /home/ga/projects/acme-services

# Create project structure
BASE_DIR="/home/ga/projects/acme-services"
mkdir -p "$BASE_DIR/api" "$BASE_DIR/cron" "$BASE_DIR/gateway"

# ------------------------------------------------------------------
# 1. ACME-API Setup
# ------------------------------------------------------------------
echo "Creating ACME API source..."
cat > "$BASE_DIR/api/app.py" << 'EOF'
from flask import Flask
import os

app = Flask(__name__)

@app.route('/health')
def health():
    return {"status": "healthy"}, 200

@app.route('/')
def index():
    return {"service": "acme-api", "version": "1.0.0"}

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

cat > "$BASE_DIR/api/requirements.txt" << 'EOF'
flask==3.0.0
EOF

# Create temporary Dockerfile for production build
cat > "$BASE_DIR/api/Dockerfile" << 'EOF'
FROM python:3.11-slim
# Install curl for healthcheck
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*
WORKDIR /opt/api
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
# Create non-root user
RUN useradd -m appuser
USER appuser
HEALTHCHECK --interval=30s --timeout=3s CMD curl -f http://localhost:5000/health || exit 1
EXPOSE 5000
CMD ["python", "app.py"]
EOF

# ------------------------------------------------------------------
# 2. ACME-CRON Setup
# ------------------------------------------------------------------
echo "Creating ACME CRON source..."
cat > "$BASE_DIR/cron/scheduler.py" << 'EOF'
import time
import os
import sys

interval = int(os.environ.get('SCHEDULE_INTERVAL', '60'))
log_level = os.environ.get('LOG_LEVEL', 'INFO')

print(f"Starting scheduler with interval {interval}s, Log Level: {log_level}")

def run_job():
    print(f"[{log_level}] Job executed at {time.time()}")

if __name__ == "__main__":
    while True:
        run_job()
        time.sleep(interval)
EOF

cat > "$BASE_DIR/cron/requirements.txt" << 'EOF'
requests==2.31.0
EOF

cat > "$BASE_DIR/cron/Dockerfile" << 'EOF'
FROM python:3.11-slim
WORKDIR /opt/cron
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
ENV SCHEDULE_INTERVAL=300
ENV LOG_LEVEL=INFO
# Specific Entrypoint/Cmd pattern
ENTRYPOINT ["python"]
CMD ["scheduler.py"]
EOF

# ------------------------------------------------------------------
# 3. ACME-GATEWAY Setup
# ------------------------------------------------------------------
echo "Creating ACME GATEWAY source..."
cat > "$BASE_DIR/gateway/nginx.conf" << 'EOF'
server {
    listen 80;
    server_name localhost;

    location / {
        root /usr/share/nginx/html;
        index index.html index.htm;
    }

    location /api/ {
        proxy_pass http://acme-api:5000/;
    }

    error_page 500 502 503 504 /50x.html;
    location = /50x.html {
        root /usr/share/nginx/html;
    }
}
EOF

cat > "$BASE_DIR/gateway/Dockerfile" << 'EOF'
FROM nginx:1.24-alpine
RUN rm /etc/nginx/conf.d/default.conf
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
EOF

# ------------------------------------------------------------------
# BUILD PRODUCTION IMAGES
# ------------------------------------------------------------------
echo "Building production images (DOCKER_BUILDKIT=0 for readable history)..."
export DOCKER_BUILDKIT=0

docker build -t acme-api:production "$BASE_DIR/api"
docker build -t acme-cron:production "$BASE_DIR/cron"
docker build -t acme-gateway:production "$BASE_DIR/gateway"

echo "Images built:"
docker images | grep "acme-"

# ------------------------------------------------------------------
# DESTROY EVIDENCE (The Task Setup)
# ------------------------------------------------------------------
echo "Removing Dockerfiles..."
rm "$BASE_DIR/api/Dockerfile"
rm "$BASE_DIR/cron/Dockerfile"
rm "$BASE_DIR/gateway/Dockerfile"

# Set ownership
chown -R ga:ga "$BASE_DIR"

# Ensure Desktop exists
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# Record start time
date +%s > /tmp/task_start_time.txt

# Open terminal
su - ga -c "DISPLAY=:1 gnome-terminal --maximize -- bash -c 'cd ~/projects/acme-services && echo \"Docker Image Reconstruction Task\"; echo \"Warning: Original Dockerfiles are LOST.\"; echo \"Production images are available (docker images). source code is in current dir.\"; echo \"Good luck.\"; exec bash'" > /tmp/terminal.log 2>&1 &
sleep 2

take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="