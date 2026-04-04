#!/bin/bash
echo "=== Setting up compose_production_hardening ==="

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

APP_DIR="/home/ga/webapp"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/app" "$APP_DIR/nginx"

# --- Python Flask application ---
cat > "$APP_DIR/app/app.py" << 'PYEOF'
import os
import redis
from flask import Flask, jsonify

app = Flask(__name__)

REDIS_HOST = os.environ.get("REDIS_HOST", "redis")
REDIS_PORT = int(os.environ.get("REDIS_PORT", "6379"))

def get_redis():
    try:
        r = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, socket_connect_timeout=2, socket_timeout=2)
        r.ping()
        return r
    except Exception:
        return None

@app.route('/')
def index():
    r = get_redis()
    if r:
        try:
            visits = r.incr('visit_count')
            cache_status = "connected"
        except Exception:
            visits = -1
            cache_status = "error"
    else:
        visits = -1
        cache_status = "disconnected"
    return jsonify({
        "service": "webapp",
        "status": "ok",
        "visits": visits,
        "cache": cache_status
    })

@app.route('/health')
def health():
    return jsonify({"status": "ok"})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
PYEOF

cat > "$APP_DIR/app/requirements.txt" << 'EOF'
flask==3.0.3
redis==5.0.1
EOF

cat > "$APP_DIR/app/Dockerfile" << 'EOF'
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
EXPOSE 5000
CMD ["python", "app.py"]
EOF

# --- Nginx reverse proxy ---
cat > "$APP_DIR/nginx/nginx.conf" << 'EOF'
events { worker_processes 1; }
http {
    server {
        listen 80;
        location / {
            proxy_pass http://app:5000;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
        }
        location /health {
            return 200 "healthy\n";
            add_header Content-Type text/plain;
        }
    }
}
EOF

# --- BASIC (unhardened) docker-compose.yml ---
# This is a development compose — no health checks, no resource limits,
# no proper restart policies, flat networking (single default network)
cat > "$APP_DIR/docker-compose.yml" << 'EOF'
services:
  nginx:
    image: nginx:1.24-alpine
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
    ports:
      - "9080:80"
    depends_on:
      - app

  app:
    build: ./app
    environment:
      - REDIS_HOST=redis
      - REDIS_PORT=6379
    depends_on:
      - redis

  redis:
    image: redis:7-alpine
EOF

# Note: Missing production features:
# 1. No healthcheck for any service
# 2. No resource limits (no deploy.resources.limits)
# 3. No restart policies
# 4. No network isolation (everything on default bridge)

# Stop any previous instance
cd "$APP_DIR" && docker compose down -v --remove-orphans 2>/dev/null || true

# Build the app image (so it exists in cache)
echo "Pre-building app image..."
cd "$APP_DIR"
docker compose build 2>&1 | tail -3

# Start the basic (unhardened) stack so agent can see it running
echo "Starting basic stack..."
docker compose up -d 2>&1 | tail -5
sleep 5

# Verify basic stack is up
if docker compose ps --format "{{.Service}}:{{.State}}" 2>/dev/null | grep -q "nginx:running"; then
    echo "Basic stack running at http://localhost:9080"
else
    echo "Warning: basic stack may not be fully up"
fi

# Record initial compose file mtime
COMPOSE_MTIME=$(stat -c %Y "$APP_DIR/docker-compose.yml" 2>/dev/null || echo "0")
echo "$COMPOSE_MTIME" > /tmp/initial_compose_mtime

date +%s > /tmp/task_start_timestamp

chown -R ga:ga "$APP_DIR"
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Webapp at $APP_DIR running at http://localhost:9080"
echo "Basic stack running — agent must harden it for production"
