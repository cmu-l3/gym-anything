#!/bin/bash
set -e
echo "=== Setting up Docker Secrets Migration Task ==="

# Source utilities (if available in the env, otherwise define minimal ones)
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
else
    # Fallback for local testing
    wait_for_docker() { sleep 5; }
    take_screenshot() { echo "Screenshot placeholder"; }
fi

wait_for_docker

# Define Project Paths
PROJECT_DIR="/home/ga/projects/acme-store"
API_DIR="$PROJECT_DIR/api"
NGINX_DIR="$PROJECT_DIR/nginx"

# Clean up any previous run
rm -rf "$PROJECT_DIR"
docker compose -f "$PROJECT_DIR/docker-compose.yml" down -v 2>/dev/null || true
docker rm -f acme-db acme-cache acme-api acme-web 2>/dev/null || true

# Create Directories
mkdir -p "$API_DIR"
mkdir -p "$NGINX_DIR"
mkdir -p "/home/ga/Desktop"
chown -R ga:ga "/home/ga/projects"
chown -R ga:ga "/home/ga/Desktop"

# ==============================================================================
# CREATE APPLICATION FILES (Vulnerable State)
# ==============================================================================

# 1. API Application (api/app.py)
# Currently reads from ENV vars. Agent must update this to read from /run/secrets/
cat > "$API_DIR/app.py" << 'PYTHON_EOF'
import os
import time
import json
import psycopg2
import redis
from flask import Flask, jsonify

app = Flask(__name__)

# SECURITY ISSUE: These are populated from Environment Variables
# The agent must change these to read from /run/secrets/ files
DB_URL = os.environ.get('DATABASE_URL', 'postgresql://postgres:password@db:5432/acmestore')
REDIS_URL = os.environ.get('REDIS_URL', 'redis://cache:6379/0')
FLASK_SECRET = os.environ.get('FLASK_SECRET', 'default_secret')
STRIPE_KEY = os.environ.get('STRIPE_API_KEY', 'unset')

app.secret_key = FLASK_SECRET

def get_db_connection():
    # Simple retry logic for DB connection
    retries = 5
    while retries > 0:
        try:
            conn = psycopg2.connect(DB_URL)
            return conn
        except psycopg2.OperationalError:
            retries -= 1
            time.sleep(2)
    return None

@app.route('/health')
def health():
    return jsonify({"status": "healthy"})

@app.route('/api/products')
def products():
    # Mock product data
    return jsonify([
        {"id": 1, "name": "Acme Widget", "price": 19.99},
        {"id": 2, "name": "Acme Gadget", "price": 29.99},
        {"id": 3, "name": "Acme Anvil", "price": 99.99}
    ])

@app.route('/api/debug')
def debug():
    # Endpoint to help verify if secrets are loaded (simulated usage)
    return jsonify({
        "db_connected": get_db_connection() is not None,
        "stripe_key_configured": STRIPE_KEY != 'unset',
        "secret_len": len(FLASK_SECRET)
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
PYTHON_EOF

# 2. API Requirements
cat > "$API_DIR/requirements.txt" << 'EOF'
flask==3.0.0
psycopg2-binary==2.9.9
redis==5.0.1
EOF

# 3. API Dockerfile (Vulnerable)
# SECURITY ISSUE: Hardcoded ENV for Flask Secret
cat > "$API_DIR/Dockerfile" << 'DOCKERFILE_EOF'
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# VULNERABILITY: Hardcoded secret in build artifact
ENV FLASK_SECRET=my_flask_secret_key_2024

CMD ["python", "app.py"]
DOCKERFILE_EOF

# 4. Nginx Configuration
cat > "$NGINX_DIR/nginx.conf" << 'NGINX_EOF'
events {
    worker_connections 1024;
}

http {
    server {
        listen 80;
        
        location /api/ {
            proxy_pass http://acme-api:5000;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
        }
        
        location /health {
            proxy_pass http://acme-api:5000/health;
        }
    }
}
NGINX_EOF

# 5. Docker Compose File (Vulnerable)
# SECURITY ISSUES: Hardcoded secrets everywhere
cat > "$PROJECT_DIR/docker-compose.yml" << 'YAML_EOF'
services:
  db:
    image: postgres:14
    container_name: acme-db
    environment:
      # VULNERABILITY 1
      POSTGRES_PASSWORD: SuperSecret123!
      POSTGRES_USER: postgres
      POSTGRES_DB: acmestore
    networks:
      - backend

  cache:
    image: redis:7-alpine
    container_name: acme-cache
    # VULNERABILITY 2
    command: redis-server --requirepass RedisPass456
    networks:
      - backend

  api:
    build: ./api
    container_name: acme-api
    depends_on:
      - db
      - cache
    environment:
      # VULNERABILITY 3, 4, 5
      DATABASE_URL: postgresql://postgres:SuperSecret123!@db:5432/acmestore
      REDIS_URL: redis://:RedisPass456@cache:6379/0
      STRIPE_API_KEY: sk_live_a1b2c3d4e5f6g7h8i9j0
    networks:
      - backend

  web:
    image: nginx:1.24-alpine
    container_name: acme-web
    ports:
      - "8080:80"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
    depends_on:
      - api
    networks:
      - backend

networks:
  backend:
YAML_EOF

# Set permissions
chown -R ga:ga "$PROJECT_DIR"

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create initial state screenshot
# We open the file manager to show the project structure
if pgrep -f "nautilus" > /dev/null; then
    pkill -f "nautilus"
fi
su - ga -c "DISPLAY=:1 nautilus --new-window $PROJECT_DIR &"
sleep 2
take_screenshot /tmp/task_initial.png

# Open terminal for user
su - ga -c "DISPLAY=:1 gnome-terminal --maximize -- bash -c 'cd $PROJECT_DIR && echo \"Docker Secrets Migration Task\"; echo \"Audit the files in this directory for hardcoded secrets.\"; echo \"Migrate them to Docker secrets and generate a report.\"; ls -la; exec bash'" > /tmp/terminal_launch.log 2>&1 &

echo "=== Task Setup Complete ==="