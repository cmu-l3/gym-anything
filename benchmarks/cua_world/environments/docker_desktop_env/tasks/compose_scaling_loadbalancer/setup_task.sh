#!/bin/bash
echo "=== Setting up Compose Scaling Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure Docker Desktop is running
if ! docker_desktop_running; then
    echo "Starting Docker Desktop..."
    su - ga -c "DISPLAY=:1 XDG_RUNTIME_DIR=/run/user/1000 /opt/docker-desktop/bin/docker-desktop > /tmp/docker-desktop.log 2>&1 &"
    wait_for_docker_daemon 60
fi

# Create project structure
PROJECT_DIR="/home/ga/scaling-app"
mkdir -p "$PROJECT_DIR/flask-app"
mkdir -p "$PROJECT_DIR/nginx"

# 1. Create Flask App
cat > "$PROJECT_DIR/flask-app/app.py" << 'EOF'
from flask import Flask
import os
import socket
import redis
import time

app = Flask(__name__)

# Connect to Redis with retry logic
def get_redis_connection():
    redis_host = os.environ.get('REDIS_HOST', 'redis')
    for i in range(5):
        try:
            return redis.Redis(host=redis_host, port=6379, decode_responses=True)
        except redis.ConnectionError:
            time.sleep(1)
    return None

r = get_redis_connection()

@app.route('/')
def hello():
    hostname = socket.gethostname()
    if r:
        try:
            visits = r.incr('hits')
            return f'Hello from {hostname}! Visit count: {visits}\n'
        except redis.ConnectionError:
            return f'Hello from {hostname}! Redis unavailable.\n'
    return f'Hello from {hostname}! No Redis connection.\n'

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

cat > "$PROJECT_DIR/flask-app/requirements.txt" << 'EOF'
flask==3.0.0
redis==5.0.1
EOF

cat > "$PROJECT_DIR/flask-app/Dockerfile" << 'EOF'
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
CMD ["python", "app.py"]
EOF

# 2. Create Initial Nginx Config (Naive - points to single host)
cat > "$PROJECT_DIR/nginx/default.conf" << 'EOF'
server {
    listen 80;
    
    location / {
        # Initial config assumes a single container named 'flask-api'
        # This will fail or only hit one instance when scaled without a resolver
        proxy_pass http://flask-api:5000;
    }
}
EOF

cat > "$PROJECT_DIR/nginx/Dockerfile" << 'EOF'
FROM nginx:alpine
COPY default.conf /etc/nginx/conf.d/default.conf
EOF

# 3. Create Initial Docker Compose (Single instance, fixed ports, explicit container name)
cat > "$PROJECT_DIR/docker-compose.yml" << 'EOF'
services:
  flask:
    build: ./flask-app
    container_name: flask-api
    ports:
      - "5000:5000"
    environment:
      - REDIS_HOST=redis
    depends_on:
      - redis
    networks:
      - app-network

  redis:
    image: redis:alpine
    container_name: app-redis
    networks:
      - app-network

  nginx:
    build: ./nginx
    container_name: app-nginx
    ports:
      - "8080:80"
    depends_on:
      - flask
    networks:
      - app-network

networks:
  app-network:
    driver: bridge
EOF

# Set permissions
chown -R ga:ga "$PROJECT_DIR"

# Clean up any previous containers
docker compose -f "$PROJECT_DIR/docker-compose.yml" down -v 2>/dev/null || true
docker rm -f flask-api app-redis app-nginx 2>/dev/null || true

# Pre-pull images to save time
docker pull python:3.11-slim >/dev/null 2>&1 &
docker pull nginx:alpine >/dev/null 2>&1 &
docker pull redis:alpine >/dev/null 2>&1 &
wait

# Open VS Code or Terminal to the project directory to help the agent start
su - ga -c "DISPLAY=:1 x-terminal-emulator --working-directory=$PROJECT_DIR &"
sleep 2

# Maximize terminal
WID=$(DISPLAY=:1 wmctrl -l | grep -i "terminal" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="