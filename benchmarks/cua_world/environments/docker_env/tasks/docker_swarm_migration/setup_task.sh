#!/bin/bash
set -e
echo "=== Setting up Docker Swarm Migration Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Helper if shared utils missing
if ! type wait_for_docker &>/dev/null; then
    wait_for_docker() {
        for i in {1..60}; do
            if docker info > /dev/null 2>&1; then return 0; fi
            sleep 2
        done
        return 1
    }
fi

if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

# Wait for Docker daemon
wait_for_docker 60

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean slate: Leave swarm if active, remove stacks/images
if [ "$(docker info --format '{{.Swarm.LocalNodeState}}')" == "active" ]; then
    docker swarm leave --force 2>/dev/null || true
fi
docker stack rm acme-tools 2>/dev/null || true
sleep 2
docker rm -f $(docker ps -aq) 2>/dev/null || true
docker rmi acme-web:1.0 acme-api:1.0 2>/dev/null || true
docker network prune -f 2>/dev/null || true

# Create project structure
PROJECT_DIR="/home/ga/projects/acme-platform"
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR"/{web,api}

# --- Web Frontend (Nginx) ---
cat > "$PROJECT_DIR/web/nginx.conf" << 'NGINXEOF'
upstream api_backend {
    server api:5000;
}

server {
    listen 80;
    server_name _;

    location / {
        root /usr/share/nginx/html;
        index index.html;
        try_files $uri $uri/ =404;
    }

    location /api/ {
        proxy_pass http://api_backend/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_connect_timeout 5s;
        proxy_read_timeout 30s;
    }

    location /health {
        access_log off;
        return 200 '{"status":"ok","service":"web"}';
        add_header Content-Type application/json;
    }
}
NGINXEOF

cat > "$PROJECT_DIR/web/index.html" << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>AcmeCorp Platform</title>
    <style>
        body { font-family: -apple-system, sans-serif; max-width: 800px; margin: 50px auto; padding: 20px; }
        h1 { color: #2d3748; }
        .status { padding: 10px; background: #c6f6d5; border-radius: 4px; margin: 10px 0; }
    </style>
</head>
<body>
    <h1>AcmeCorp Developer Platform</h1>
    <div class="status">✅ Web frontend operational</div>
    <p>Services: <a href="/api/health">API Health</a> | <a href="/health">Web Health</a></p>
    <p>Version: 1.0.0 | Deployed via Docker Swarm</p>
</body>
</html>
HTMLEOF

cat > "$PROJECT_DIR/web/Dockerfile" << 'WEBDOCKEREOF'
FROM nginx:1.24-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY index.html /usr/share/nginx/html/index.html
EXPOSE 80
HEALTHCHECK --interval=10s --timeout=3s --retries=3 \
    CMD wget -qO- http://localhost/health || exit 1
WEBDOCKEREOF

# --- API Backend (Flask) ---
cat > "$PROJECT_DIR/api/requirements.txt" << 'REQEOF'
flask==3.0.0
redis==5.0.1
psycopg2-binary==2.9.9
gunicorn==21.2.0
REQEOF

cat > "$PROJECT_DIR/api/app.py" << 'APPEOF'
import os
import json
import time
from flask import Flask, jsonify

app = Flask(__name__)

@app.route("/")
def root():
    return jsonify({"service": "acme-api", "version": "1.0.0"})

@app.route("/health")
def health():
    checks = {"api": "ok"}
    # Check Redis connectivity
    try:
        import redis
        r = redis.from_url(os.environ.get("REDIS_URL", "redis://cache:6379/0"), socket_timeout=2)
        r.ping()
        checks["cache"] = "ok"
    except Exception as e:
        checks["cache"] = f"degraded: {str(e)[:50]}"
    
    status_code = 200 if checks["api"] == "ok" else 503
    return jsonify({"status": "healthy" if status_code == 200 else "degraded", "checks": checks}), status_code

@app.route("/api/products")
def products():
    return jsonify([
        {"id": 1, "name": "DevKit Pro", "price": 299.99},
        {"id": 2, "name": "CI Pipeline Starter", "price": 149.99}
    ])

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
APPEOF

cat > "$PROJECT_DIR/api/Dockerfile" << 'APIDOCKEREOF'
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
EXPOSE 5000
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "app:app"]
APIDOCKEREOF

# --- Original docker-compose.yml (Legacy) ---
cat > "$PROJECT_DIR/docker-compose.yml" << 'COMPOSEEOF'
version: "3.8"

services:
  web:
    build:
      context: ./web
      dockerfile: Dockerfile
    ports:
      - "8080:80"
    depends_on:
      - api
    networks:
      - frontend
      - backend
    restart: always

  api:
    build:
      context: ./api
      dockerfile: Dockerfile
    environment:
      - REDIS_URL=redis://cache:6379/0
    depends_on:
      - db
      - cache
    networks:
      - backend
    restart: unless-stopped

  db:
    image: postgres:14
    environment:
      POSTGRES_PASSWORD: password
    networks:
      - backend

  cache:
    image: redis:7-alpine
    networks:
      - backend

networks:
  frontend:
    driver: bridge
  backend:
    driver: bridge
COMPOSEEOF

# --- Migration Notes ---
cat > "$PROJECT_DIR/MIGRATION_NOTES.md" << 'NOTESEOF'
# Swarm Migration Request

We need to move this from Docker Compose to Swarm.

Requirements:
1. Initialize Swarm.
2. Build images `acme-web:1.0` and `acme-api:1.0` locally.
3. Create `docker-stack.yml`:
   - Replace build directives with image tags.
   - Use overlay network `acme-net`.
   - Web: 3 replicas, update policy (parallelism 1, delay 10s), mem limit 256MB.
   - API: 2 replicas, mem limit 256MB.
   - DB/Cache: 1 replica each.
4. Deploy stack as `acme-tools`.
NOTESEOF

# Set permissions
chown -R ga:ga "$PROJECT_DIR"

# Ensure terminal is open
su - ga -c "DISPLAY=:1 gnome-terminal --maximize --working-directory='$PROJECT_DIR' -- bash -c 'cat MIGRATION_NOTES.md; echo; ls -la; exec bash'" > /tmp/terminal.log 2>&1 &
sleep 5

# Capture initial state
take_screenshot /tmp/task_initial.png
echo "setup_complete" > /tmp/setup_complete.flag

echo "=== Setup Complete ==="