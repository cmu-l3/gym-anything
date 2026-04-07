#!/bin/bash
echo "=== Setting up broken_compose_diagnosis ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions
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

APP_DIR="/home/ga/app-debug"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/flask" "$APP_DIR/nginx"

# --- Flask application (real-world pattern) ---
cat > "$APP_DIR/flask/app.py" << 'PYEOF'
import os
import time
import mysql.connector
from flask import Flask, jsonify

app = Flask(__name__)

def get_db_connection():
    host = os.environ.get('MYSQL_HOST', 'db')
    user = os.environ.get('MYSQL_USER', 'flask')
    password = os.environ.get('MYSQL_PASSWORD', 'flask')
    database = os.environ.get('MYSQL_DB', 'flaskdb')
    for attempt in range(5):
        try:
            conn = mysql.connector.connect(
                host=host, user=user,
                password=password, database=database,
                connection_timeout=5
            )
            return conn
        except mysql.connector.Error:
            time.sleep(2)
    return None

@app.route('/')
def index():
    return jsonify({"status": "ok", "service": "Flask API", "version": "1.0"})

@app.route('/health')
def health():
    conn = get_db_connection()
    if conn:
        conn.close()
        return jsonify({"status": "healthy", "db": "connected"})
    return jsonify({"status": "degraded", "db": "unreachable"}), 503

@app.route('/items')
def items():
    conn = get_db_connection()
    if not conn:
        return jsonify({"error": "DB unavailable"}), 503
    cur = conn.cursor()
    cur.execute("SHOW TABLES")
    tables = cur.fetchall()
    conn.close()
    return jsonify({"tables": [t[0] for t in tables]})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False)
PYEOF

cat > "$APP_DIR/flask/requirements.txt" << 'EOF'
flask==3.0.3
mysql-connector-python==8.3.0
EOF

cat > "$APP_DIR/flask/Dockerfile" << 'EOF'
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
EXPOSE 5000
ENV FLASK_APP=app.py
CMD ["python", "-m", "flask", "run", "--host=0.0.0.0", "--port=5000"]
EOF

# --- Nginx config ---
cat > "$APP_DIR/nginx/nginx.conf" << 'EOF'
server {
    listen 80;
    server_name localhost;

    location / {
        proxy_pass http://flask:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 30;
        proxy_connect_timeout 10;
    }
}
EOF

# --- BUGGY docker-compose.yml (3 deliberate bugs) ---
cat > "$APP_DIR/docker-compose.yml" << 'EOF'
services:
  flask:
    build:
      context: flask
    environment:
      MYSQL_HOST: localhost
      MYSQL_USER: flask
      MYSQL_PASSWORD: flask
      MYSQL_DB: flaskdb
    networks:
      - frontnet
    restart: unless-stopped
    depends_on:
      - db

  nginx:
    image: nginx:1.24-alpine
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/conf.d/default.conf:ro
    ports:
      - "8080:80"
    networks:
      - frontnet
    depends_on:
      - flask

  db:
    image: mysql:8.0
    environment:
      MYSQL_DATABASE: flaskdb
      MYSQL_USER: flask
      MYSQL_PASSWORD: flask
      MYSQL_ROOT_PASSWORD: S3cur3R00t!
    volumes:
      - db_data:/var/lib/mysql
    networks:
      - backnet
    restart: unless-stopped

networks:
  frontnet:
  backnet:
EOF

# Note: 3 bugs in this file:
# BUG 1: MYSQL_HOST=localhost (should be MYSQL_HOST=db)
# BUG 2: flask only in frontnet, not backnet (can't reach db)
# BUG 3: volumes: section missing at top level (db_data not declared)

# Tear down any previous version
cd "$APP_DIR" && docker compose down -v --remove-orphans 2>/dev/null || true

# Record baseline
INITIAL_RUNNING=$(docker ps --format "{{.Names}}" 2>/dev/null | wc -l | tr -d ' ')
echo "$INITIAL_RUNNING" > /tmp/initial_running_count

COMPOSE_MTIME=$(stat -c %Y "$APP_DIR/docker-compose.yml" 2>/dev/null || echo "0")
echo "$COMPOSE_MTIME" > /tmp/initial_compose_mtime

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

chown -R ga:ga "$APP_DIR"
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Broken compose app ready at: $APP_DIR"
echo "Run: cd $APP_DIR && docker compose up -d"
echo "Expected failure — agent must diagnose and fix 3 bugs"
