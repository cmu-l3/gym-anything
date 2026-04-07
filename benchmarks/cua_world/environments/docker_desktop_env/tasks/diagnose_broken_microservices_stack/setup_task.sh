#!/bin/bash
echo "=== Setting up diagnose_broken_microservices_stack task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# --- Docker daemon setup ---
# After loading from a post_start checkpoint, Docker Desktop's socket may be
# stale. Try Docker Desktop first; if it doesn't respond, fall back to the
# system Docker daemon (/var/run/docker.sock) which is always reliable.

# Track which Docker daemon we end up using
USED_SYSTEM_FALLBACK=false

# 1. Try Docker Desktop daemon (quick check)
if ! timeout 10 docker info > /dev/null 2>&1; then
    echo "Docker Desktop daemon not ready, restarting..."
    pkill -f 'com.docker.backend' 2>/dev/null || true
    pkill -f 'docker-desktop' 2>/dev/null || true
    sleep 3
    su - ga -c "DISPLAY=:1 XDG_RUNTIME_DIR=/run/user/1000 setsid /opt/docker-desktop/bin/docker-desktop > /tmp/docker-desktop-restart.log 2>&1 &"
    # Wait up to 90s for Docker Desktop daemon
    DAEMON_READY=false
    for i in $(seq 1 45); do
        if timeout 5 docker info > /dev/null 2>&1; then
            echo "Docker Desktop daemon ready after $((i*2))s"
            DAEMON_READY=true
            break
        fi
        sleep 2
    done
    if [ "$DAEMON_READY" != "true" ]; then
        echo "Docker Desktop daemon not responding, falling back to system Docker..."
        export DOCKER_HOST=unix:///var/run/docker.sock
        USED_SYSTEM_FALLBACK=true
        if ! timeout 10 docker info > /dev/null 2>&1; then
            echo "System Docker daemon also not ready, waiting..."
            wait_for_docker_daemon 60
        fi
    fi
else
    echo "Docker Desktop daemon is ready"
fi
echo "Using DOCKER_HOST=${DOCKER_HOST:-default}"

PROJECT_DIR="/home/ga/microservices-debug"

# Clean up any existing project
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR"/{app,nginx,db}

# ================================================================
# Flask application (CORRECT - agent must NOT modify this file)
# ================================================================
cat > "$PROJECT_DIR/app/app.py" << 'PYEOF'
import os
from flask import Flask, jsonify
import psycopg2
import redis

app = Flask(__name__)


@app.route('/api/health')
def health():
    result = {"status": "healthy"}
    try:
        conn = psycopg2.connect(os.environ['DATABASE_URL'])
        cur = conn.cursor()
        cur.execute("SELECT 1")
        cur.close()
        conn.close()
        result["database"] = "connected"
    except Exception as e:
        result["database"] = "error: {}".format(str(e)[:200])
        result["status"] = "degraded"
    try:
        r = redis.from_url(os.environ['REDIS_URL'])
        r.ping()
        result["cache"] = "connected"
    except Exception as e:
        result["cache"] = "error: {}".format(str(e)[:200])
        result["status"] = "degraded"
    return jsonify(result)


@app.route('/api/items')
def items():
    conn = psycopg2.connect(os.environ['DATABASE_URL'])
    cur = conn.cursor()
    cur.execute("SELECT id, name, price FROM items ORDER BY id")
    rows = [{"id": r[0], "name": r[1], "price": float(r[2])} for r in cur.fetchall()]
    cur.close()
    conn.close()
    return jsonify(rows)


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
PYEOF

cat > "$PROJECT_DIR/app/Dockerfile" << 'DEOF'
FROM python:3.11-slim
WORKDIR /app
RUN pip install --no-cache-dir flask psycopg2-binary redis
COPY app.py .
EXPOSE 5000
CMD ["python", "app.py"]
DEOF

# ================================================================
# Nginx configuration
# BUG 1: upstream port is 8000 but Flask listens on 5000
# ================================================================
cat > "$PROJECT_DIR/nginx/nginx.conf" << 'NGINXEOF'
upstream flask_backend {
    server flask-app:8000;
}

server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://flask_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
NGINXEOF

# ================================================================
# Database init script (CORRECT - creates items table with data)
# ================================================================
cat > "$PROJECT_DIR/db/init.sql" << 'SQLEOF'
CREATE TABLE IF NOT EXISTS items (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    price DECIMAL(10,2) NOT NULL
);

INSERT INTO items (name, price) VALUES
    ('Wireless Keyboard', 49.99),
    ('USB-C Hub', 29.99),
    ('Monitor Stand', 79.99),
    ('Mechanical Keyboard', 129.99),
    ('Webcam HD', 59.99),
    ('Laptop Cooling Pad', 34.99),
    ('Ergonomic Mouse', 44.99),
    ('USB Microphone', 69.99);
SQLEOF

# ================================================================
# Docker Compose configuration with 3 additional bugs:
#
# BUG 2: flask-app is only on the 'frontend' network.
#         db and redis are only on the 'backend' network.
#         Flask cannot resolve hostnames 'db' or 'redis'.
#
# BUG 3: DATABASE_URL references database 'production_db'
#         but POSTGRES_DB creates database 'myapp'.
#
# BUG 4: Redis is started with --requirepass secretredis123
#         but REDIS_URL has no password in the connection string.
# ================================================================
cat > "$PROJECT_DIR/docker-compose.yml" << 'COMPOSEEOF'
services:
  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - flask-app
    networks:
      - frontend

  flask-app:
    build: ./app
    environment:
      - DATABASE_URL=postgresql://appuser:apppass@db:5432/production_db
      - REDIS_URL=redis://redis:6379/0
    depends_on:
      - db
      - redis
    networks:
      - frontend

  db:
    image: postgres:15-alpine
    environment:
      - POSTGRES_USER=appuser
      - POSTGRES_PASSWORD=apppass
      - POSTGRES_DB=myapp
    volumes:
      - pgdata:/var/lib/postgresql/data
      - ./db/init.sql:/docker-entrypoint-initdb.d/init.sql
    networks:
      - backend

  redis:
    image: redis:7-alpine
    command: redis-server --requirepass secretredis123
    networks:
      - backend

networks:
  frontend:
  backend:

volumes:
  pgdata:
COMPOSEEOF

# Set ownership so ga user can edit all files
chown -R ga:ga "$PROJECT_DIR"

# ================================================================
# Pre-pull all required Docker images
# ================================================================
echo "Pre-pulling Docker images..."
docker pull python:3.11-slim >/dev/null 2>&1 || true
docker pull nginx:alpine >/dev/null 2>&1 || true
docker pull postgres:15-alpine >/dev/null 2>&1 || true
docker pull redis:7-alpine >/dev/null 2>&1 || true

# ================================================================
# Ensure ga user uses the same Docker daemon we're using
# ================================================================
if [ "$USED_SYSTEM_FALLBACK" = "true" ]; then
    # Only switch ga to default context if we fell back to system Docker
    echo "Switching ga to default Docker context (system fallback)..."
    su - ga -c "docker context use default" 2>/dev/null || true
else
    # Docker Desktop is working — make sure ga uses it
    echo "Ensuring ga uses desktop-linux Docker context..."
    su - ga -c "docker context use desktop-linux" 2>/dev/null || true
fi

# Clean up any previous containers from other runs
cd "$PROJECT_DIR"
docker compose down -v 2>/dev/null || true

# ================================================================
# Build and start the (broken) stack
# ================================================================
echo "Building and starting the stack..."
docker compose build --quiet 2>/dev/null || docker compose build 2>&1 | tail -5
docker compose up -d 2>/dev/null || docker compose up -d 2>&1 | tail -5

# Wait for services to attempt startup (postgres needs time to init)
echo "Waiting for services to stabilize..."
sleep 15

# Verify services started
echo "Running containers:"
docker compose ps 2>/dev/null || true

# ================================================================
# Delete stale outputs BEFORE recording timestamp
# ================================================================
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/health_response.json 2>/dev/null || true
rm -f /tmp/items_response.json 2>/dev/null || true

# Record task start time
echo "$(date +%s)" > /tmp/task_start_time.txt

# Open terminal in project directory for the agent
su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=$PROJECT_DIR &" || true
sleep 2

# Focus Docker Desktop window
focus_docker_desktop || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Stack started with 4 planted configuration bugs."
echo "Agent must diagnose and fix all issues."
