#!/bin/bash
# Setup script for docker_compose_external_bridge
# Creates two docker-compose projects with default (broken) networking

echo "=== Setting up Docker Compose External Bridge Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Start Docker Desktop and wait for daemon
if ! docker_desktop_running; then
    echo "Starting Docker Desktop..."
    su - ga -c "DISPLAY=:1 XDG_RUNTIME_DIR=/run/user/1000 /opt/docker-desktop/bin/docker-desktop > /tmp/docker-desktop.log 2>&1 &"
    sleep 10
fi

echo "Waiting for Docker daemon..."
wait_for_docker_daemon 60

# 2. Cleanup previous runs
echo "Cleaning up previous state..."
docker rm -f $(docker ps -a -q) 2>/dev/null || true
docker network rm infra-db-net infra-cache-net 2>/dev/null || true
rm -rf /home/ga/Documents/docker-projects/shared-infra
rm -rf /home/ga/Documents/docker-projects/flask-api
rm -f /home/ga/Documents/docker-projects/connectivity-report.txt

# 3. Create Project Directories
mkdir -p /home/ga/Documents/docker-projects/shared-infra
mkdir -p /home/ga/Documents/docker-projects/flask-api

# 4. Create Shared Infra Compose File (Initial State: Default Networks)
cat > /home/ga/Documents/docker-projects/shared-infra/docker-compose.yml << 'EOF'
services:
  postgres:
    image: postgres:16-alpine
    container_name: shared-postgres
    environment:
      POSTGRES_USER: appuser
      POSTGRES_PASSWORD: apppass123
      POSTGRES_DB: appdb
    ports:
      - "5432:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U appuser -d appdb"]
      interval: 5s
      timeout: 3s
      retries: 5

  redis:
    image: redis:7-alpine
    container_name: shared-redis
    ports:
      - "6379:6379"
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 3s
      retries: 5
EOF

# 5. Create Flask API App
cat > /home/ga/Documents/docker-projects/flask-api/app.py << 'EOF'
from flask import Flask, jsonify
import psycopg2
import redis
import os
import time

app = Flask(__name__)

@app.route('/health/db')
def health_db():
    try:
        conn = psycopg2.connect(
            host=os.environ.get('DB_HOST', 'shared-postgres'),
            port=os.environ.get('DB_PORT', 5432),
            user=os.environ.get('DB_USER', 'appuser'),
            password=os.environ.get('DB_PASSWORD', 'apppass123'),
            dbname=os.environ.get('DB_NAME', 'appdb'),
            connect_timeout=3
        )
        cur = conn.cursor()
        cur.execute('SELECT 1')
        cur.close()
        conn.close()
        return jsonify({"status": "ok", "service": "postgresql", "message": "Connection successful"})
    except Exception as e:
        return jsonify({"status": "error", "service": "postgresql", "error": str(e)}), 503

@app.route('/health/redis')
def health_redis():
    try:
        r = redis.Redis(
            host=os.environ.get('REDIS_HOST', 'shared-redis'),
            port=int(os.environ.get('REDIS_PORT', 6379)),
            socket_connect_timeout=3
        )
        r.ping()
        return jsonify({"status": "ok", "service": "redis", "message": "Connection successful"})
    except Exception as e:
        return jsonify({"status": "error", "service": "redis", "error": str(e)}), 503

@app.route('/')
def index():
    return jsonify({"app": "flask-api", "version": "1.0", "instructions": "Check /health/db and /health/redis"})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5050)
EOF

cat > /home/ga/Documents/docker-projects/flask-api/requirements.txt << 'EOF'
flask==3.0.0
psycopg2-binary==2.9.9
redis==5.0.1
EOF

cat > /home/ga/Documents/docker-projects/flask-api/Dockerfile << 'EOF'
FROM python:3.11-slim
WORKDIR /app
RUN pip install --no-cache-dir flask psycopg2-binary redis
COPY app.py .
EXPOSE 5050
CMD ["python", "app.py"]
EOF

# 6. Create Flask API Compose File (Initial State: Default Networks)
# Note: It tries to connect to hostnames 'shared-postgres' and 'shared-redis',
# which will fail until the external networks are configured.
cat > /home/ga/Documents/docker-projects/flask-api/docker-compose.yml << 'EOF'
services:
  api:
    build: .
    container_name: flask-api
    ports:
      - "5050:5050"
    environment:
      DB_HOST: shared-postgres
      DB_PORT: 5432
      DB_USER: appuser
      DB_PASSWORD: apppass123
      DB_NAME: appdb
      REDIS_HOST: shared-redis
      REDIS_PORT: 6379
EOF

# 7. Set permissions and timestamps
chown -R ga:ga /home/ga/Documents/docker-projects
date +%s > /tmp/task_start_time.txt

# Record initial file modification times for anti-gaming
stat -c %Y /home/ga/Documents/docker-projects/shared-infra/docker-compose.yml > /tmp/initial_mtime_infra.txt
stat -c %Y /home/ga/Documents/docker-projects/flask-api/docker-compose.yml > /tmp/initial_mtime_api.txt

# 8. Open a terminal for the user
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga/Documents/docker-projects &"
fi

# 9. Focus Docker Desktop (if running) or maximize terminal
focus_docker_desktop

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="
echo "Projects created at /home/ga/Documents/docker-projects/"