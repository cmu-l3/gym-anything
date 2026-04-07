#!/bin/bash
set -e
echo "=== Setting up Docker Compose Reverse Engineering Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Wait for Docker
if ! docker info >/dev/null 2>&1; then
    echo "Waiting for Docker daemon..."
    for i in {1..30}; do
        if docker info >/dev/null 2>&1; then break; fi
        sleep 2
    done
fi

# 1. Prepare Workspace
PROJECT_DIR="/home/ga/projects/inventory-tracker"
mkdir -p "$PROJECT_DIR/nginx"
mkdir -p "$PROJECT_DIR/api_src" # Temporary source for building the image

# 2. create Nginx Config
cat > "$PROJECT_DIR/nginx/default.conf" <<EOF
server {
    listen 80;
    location / {
        proxy_pass http://inv-api:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF

# 3. Create API Source and Build Custom Image (inv-api:latest)
# We build it here so it exists locally for the task
cat > "$PROJECT_DIR/api_src/app.py" <<'EOF'
import os
import json
from flask import Flask, jsonify
import psycopg2
import redis

app = Flask(__name__)

@app.route('/api/status')
def status():
    # Check Redis connection
    r = redis.Redis.from_url(os.environ.get('REDIS_URL', 'redis://localhost:6379/0'))
    hits = r.incr('hits')
    return jsonify({"status": "running", "hits": hits})

@app.route('/api/items')
def items():
    # Check DB connection
    try:
        conn = psycopg2.connect(os.environ.get('DATABASE_URL'))
        cur = conn.cursor()
        cur.execute("SELECT 1")
        return jsonify({"items": [{"id": 1, "name": "Widget A"}, {"id": 2, "name": "Widget B"}]})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

cat > "$PROJECT_DIR/api_src/requirements.txt" <<EOF
flask==3.0.0
psycopg2-binary==2.9.9
redis==5.0.1
EOF

cat > "$PROJECT_DIR/api_src/Dockerfile" <<EOF
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
CMD ["python", "app.py"]
EOF

echo "Building custom inv-api:latest image..."
docker build -t inv-api:latest "$PROJECT_DIR/api_src" > /dev/null 2>&1
rm -rf "$PROJECT_DIR/api_src" # Clean up source so agent only sees the image

# 4. Create Networks
echo "Creating networks..."
docker network create inv-backend
docker network create inv-frontend

# 5. Create Volume
echo "Creating volume..."
docker volume create inv-pgdata

# 6. Launch "Lost" Containers
echo "Launching orphan containers..."

# DB: Postgres
docker run -d \
  --name inv-db \
  --network inv-backend \
  -e POSTGRES_DB=inventory \
  -e POSTGRES_USER=invadmin \
  -e POSTGRES_PASSWORD=secretpass42 \
  -v inv-pgdata:/var/lib/postgresql/data \
  --health-cmd="pg_isready -U invadmin -d inventory" \
  postgres:14

# Cache: Redis with custom command
docker run -d \
  --name inv-cache \
  --network inv-backend \
  --health-cmd="redis-cli ping" \
  redis:7-alpine \
  redis-server --maxmemory 64mb --maxmemory-policy allkeys-lru

# API: Custom image, dual networks
docker run -d \
  --name inv-api \
  --network inv-backend \
  -e DATABASE_URL="postgresql://invadmin:secretpass42@inv-db:5432/inventory" \
  -e REDIS_URL="redis://inv-cache:6379/0" \
  -e FLASK_ENV=production \
  inv-api:latest

# Connect API to frontend network too
docker network connect inv-frontend inv-api

# Web: Nginx
docker run -d \
  --name inv-web \
  --network inv-frontend \
  -p 8080:80 \
  -v "$PROJECT_DIR/nginx/default.conf:/etc/nginx/conf.d/default.conf:ro" \
  nginx:1.24-alpine

# 7. Final Cleanup and State Recording
chown -R ga:ga "$PROJECT_DIR"

# Record IDs of original containers to distinguish from new ones later
docker inspect --format '{{.Id}}' inv-db inv-cache inv-api inv-web > /tmp/original_container_ids.txt 2>/dev/null || true

# Timestamp
date +%s > /tmp/task_start_time.txt

# Setup Terminal
su - ga -c "DISPLAY=:1 gnome-terminal --maximize -- bash -c 'cd $PROJECT_DIR && echo \"Infrastructure Disaster Recovery\"; echo \"4 containers are running. The compose file is missing.\"; echo \"Project dir: $PROJECT_DIR\"; echo; docker ps; exec bash'" > /dev/null 2>&1 &

take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="