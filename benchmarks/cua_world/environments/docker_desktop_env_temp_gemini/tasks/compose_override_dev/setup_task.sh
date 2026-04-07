#!/bin/bash
set -e
echo "=== Setting up compose_override_dev task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Docker daemon
wait_for_docker_daemon 60

# Define project path
PROJECT_DIR="/home/ga/Documents/docker-projects/webapp"
mkdir -p "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR/api"
mkdir -p "$PROJECT_DIR/web"
mkdir -p "$PROJECT_DIR/web/static"
mkdir -p "$PROJECT_DIR/init-db"

# 1. Create base docker-compose.yml (Production config)
cat > "$PROJECT_DIR/docker-compose.yml" << 'EOF'
services:
  web:
    image: nginx:alpine
    container_name: webapp-web
    ports:
      - "8080:80"
    volumes:
      - ./web/nginx.conf:/etc/nginx/conf.d/default.conf:ro
      - ./web/static:/usr/share/nginx/html:ro
    depends_on:
      - api
    restart: unless-stopped

  api:
    build: ./api
    container_name: webapp-api
    expose:
      - "5000"
    environment:
      DB_HOST: db
      DB_PORT: "5432"
      DB_USER: webapp
      DB_PASSWORD: webapp_secret
      DB_NAME: webapp_db
    depends_on:
      - db
    restart: unless-stopped

  db:
    image: postgres:16-alpine
    container_name: webapp-db
    environment:
      POSTGRES_USER: webapp
      POSTGRES_PASSWORD: webapp_secret
      POSTGRES_DB: webapp_db
    volumes:
      - db_data:/var/lib/postgresql/data
      - ./init-db:/docker-entrypoint-initdb.d:ro
    restart: unless-stopped

volumes:
  db_data:
EOF

# 2. Create API files
cat > "$PROJECT_DIR/api/app.py" << 'EOF'
from flask import Flask, jsonify
import os
import psycopg2

app = Flask(__name__)

@app.route('/')
def index():
    return jsonify({
        "service": "webapp-api",
        "debug": os.environ.get("FLASK_DEBUG", "0"),
        "env": os.environ.get("FLASK_ENV", "production")
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

cat > "$PROJECT_DIR/api/requirements.txt" << 'EOF'
flask==3.0.0
psycopg2-binary==2.9.9
gunicorn==21.2.0
EOF

cat > "$PROJECT_DIR/api/Dockerfile" << 'EOF'
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
EXPOSE 5000
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "app:app"]
EOF

# 3. Create Nginx files
cat > "$PROJECT_DIR/web/nginx.conf" << 'EOF'
upstream api_upstream {
    server api:5000;
}
server {
    listen 80;
    server_name localhost;
    location / {
        root /usr/share/nginx/html;
        try_files $uri $uri/ @api;
    }
    location @api {
        proxy_pass http://api_upstream;
        proxy_set_header Host $host;
    }
}
EOF

cat > "$PROJECT_DIR/web/static/index.html" << 'EOF'
<!DOCTYPE html>
<html><body><h1>Webapp Ready</h1></body></html>
EOF

# 4. Create DB init script
cat > "$PROJECT_DIR/init-db/init.sql" << 'EOF'
CREATE TABLE users (id SERIAL PRIMARY KEY, username VARCHAR(50));
INSERT INTO users (username) VALUES ('admin'), ('dev');
EOF

# Set permissions
chown -R ga:ga "$PROJECT_DIR"

# Calculate MD5 of base compose file to detect unauthorized modification
md5sum "$PROJECT_DIR/docker-compose.yml" | awk '{print $1}' > /tmp/base_compose_md5.txt

# Pre-build the API image to speed up the task for the agent
# (The agent will still need to bring it up, but build step will be cached/fast)
echo "Pre-building API image..."
cd "$PROJECT_DIR"
su - ga -c "docker compose build api"

# Ensure clean state (no running containers from this project)
su - ga -c "docker compose down -v 2>/dev/null" || true

# Focus Docker Desktop
focus_docker_desktop

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="