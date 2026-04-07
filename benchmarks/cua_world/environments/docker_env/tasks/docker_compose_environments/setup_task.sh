#!/bin/bash
# Setup script for docker_compose_environments task

set -e
echo "=== Setting up Docker Compose Environments Task ==="

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

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 1. Create Project Directory
PROJECT_DIR="/home/ga/projects/acme-analytics"
mkdir -p "$PROJECT_DIR/api"
mkdir -p "$PROJECT_DIR/nginx"

# 2. Create Python API Code
cat > "$PROJECT_DIR/api/app.py" << 'EOF'
import os
import time
import psycopg2
import redis
from flask import Flask, jsonify

app = Flask(__name__)

def get_db_connection():
    try:
        conn = psycopg2.connect(os.environ['DATABASE_URL'])
        return True
    except:
        return False

def get_redis_connection():
    try:
        r = redis.from_url(os.environ['REDIS_URL'])
        return r.ping()
    except:
        return False

@app.route('/api/health')
def health():
    return jsonify({"status": "healthy", "environment": os.environ.get("FLASK_DEBUG", "unknown")})

@app.route('/api/stats')
def stats():
    db_status = get_db_connection()
    redis_status = get_redis_connection()
    return jsonify({
        "database": "connected" if db_status else "disconnected",
        "redis": "connected" if redis_status else "disconnected"
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

cat > "$PROJECT_DIR/api/requirements.txt" << 'EOF'
flask==3.0.0
psycopg2-binary==2.9.9
redis==5.0.1
EOF

cat > "$PROJECT_DIR/api/Dockerfile" << 'EOF'
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
CMD ["python", "app.py"]
EOF

# 3. Create Nginx Config
cat > "$PROJECT_DIR/nginx/nginx.conf" << 'EOF'
events { worker_connections 1024; }
http {
    server {
        listen 80;
        location /api/ {
            proxy_pass http://api:5000/api/;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
        }
    }
}
EOF

cat > "$PROJECT_DIR/nginx/Dockerfile" << 'EOF'
FROM nginx:1.24-alpine
COPY nginx.conf /etc/nginx/nginx.conf
EOF

# 4. Create Monolithic Compose File (The Problem)
cat > "$PROJECT_DIR/docker-compose.monolith.yml" << 'EOF'
version: '3.8'
services:
  db:
    image: postgres:14
    environment:
      POSTGRES_USER: analytics
      POSTGRES_PASSWORD: analytics123
      POSTGRES_DB: analytics
    ports:
      - "5432:5432"  # BAD: Exposed to host
    volumes:
      - db-data:/var/lib/postgresql/data

  cache:
    image: redis:7-alpine
    ports:
      - "6379:6379"  # BAD: Exposed to host
    # MISSING: Authentication

  api:
    image: acme-analytics-api:latest
    build: ./api
    ports:
      - "5000:5000"  # BAD: Exposed to host
    environment:
      FLASK_DEBUG: 1  # BAD: Hardcoded debug mode
      DATABASE_URL: postgresql://analytics:analytics123@db:5432/analytics
      REDIS_URL: redis://cache:6379/0
    volumes:
      - ./api:/app  # BAD: Hardcoded development mount
    depends_on:
      - db
      - cache

  nginx:
    build: ./nginx
    ports:
      - "8080:80"
    depends_on:
      - api

volumes:
  db-data:
EOF

# 5. Build the base API image so the agent doesn't waste time
echo "Pre-building API image..."
export DOCKER_BUILDKIT=1
docker build -t acme-analytics-api:latest "$PROJECT_DIR/api" > /tmp/build.log 2>&1
docker build -t acme-analytics-nginx:latest "$PROJECT_DIR/nginx" >> /tmp/build.log 2>&1

# 6. Set permissions
chown -R ga:ga "$PROJECT_DIR"

# 7. Prepare terminal
su - ga -c "DISPLAY=:1 gnome-terminal --maximize -- bash -c 'cd ~/projects/acme-analytics && echo \"Refactoring Task Ready\"; echo \"Source: docker-compose.monolith.yml\"; ls -la; exec bash'" > /tmp/terminal.log 2>&1 &
sleep 3

# 8. Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="