#!/bin/bash
# Setup script for docker_container_formalization
set -e
echo "=== Setting up Docker Container Formalization Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

wait_for_docker

# Cleanup any previous state
echo "Cleaning up..."
docker rm -f acme-frontend acme-api acme-cron 2>/dev/null || true
rm -rf /home/ga/projects/reproducible-images 2>/dev/null || true
mkdir -p /home/ga/projects/reproducible-images/{frontend,api,cron}
mkdir -p /home/ga/Desktop
chown -R ga:ga /home/ga/projects /home/ga/Desktop

# ------------------------------------------------------------------
# 1. acme-frontend (Modified Nginx)
# ------------------------------------------------------------------
echo "Starting acme-frontend..."
# Start base
docker run -d --name acme-frontend -p 8080:80 nginx:1.24-alpine

# Apply manual changes via exec
# - Install curl
docker exec acme-frontend apk add --no-cache curl
# - Custom index page
docker exec acme-frontend sh -c "echo '<!DOCTYPE html><html><body><h1>AcmeCorp Dashboard</h1><p>Status: Active</p></body></html>' > /usr/share/nginx/html/index.html"
# - Custom config with health endpoint
docker exec acme-frontend sh -c "cat > /etc/nginx/conf.d/default.conf <<EOF
server {
    listen       80;
    server_name  localhost;
    location / {
        root   /usr/share/nginx/html;
        index  index.html index.htm;
    }
    location /healthz {
        return 200 'OK';
        add_header Content-Type text/plain;
    }
}
EOF"
# Reload nginx to apply config
docker exec acme-frontend nginx -s reload

# ------------------------------------------------------------------
# 2. acme-api (Modified Python/Flask)
# ------------------------------------------------------------------
echo "Starting acme-api..."
# We use a long shell command to simulate the 'manual' setup history being visible in inspect
docker run -d --name acme-api -p 8000:8000 python:3.11-slim sh -c "
    pip install flask gunicorn requests && \
    mkdir -p /app && \
    echo \"from flask import Flask, jsonify
app = Flask(__name__)

@app.route('/api/status')
def status():
    return jsonify({'status': 'ok', 'service': 'acme-api', 'version': '1.0.1'})

@app.route('/api/products')
def products():
    return jsonify(['widget', 'gadget', 'sprocket'])\" > /app/server.py && \
    cd /app && \
    exec gunicorn --bind 0.0.0.0:8000 server:app
"

# ------------------------------------------------------------------
# 3. acme-cron (Modified Alpine)
# ------------------------------------------------------------------
echo "Starting acme-cron..."
docker run -d --name acme-cron alpine:3.18 sh -c "
    apk add --no-cache bash curl jq && \
    mkdir -p /app && \
    echo '#!/bin/bash' > /app/healthcheck.sh && \
    echo 'echo \"\$(date) - Health check running\" >> /var/log/healthcheck.log' >> /app/healthcheck.sh && \
    chmod +x /app/healthcheck.sh && \
    echo '{\"service_url\": \"http://acme-api:8000\"}' > /app/config.json && \
    while true; do /app/healthcheck.sh; sleep 60; done
"

# Record task start time
date +%s > /tmp/task_start_timestamp

# Prepare instructions in terminal
su - ga -c "DISPLAY=:1 gnome-terminal --maximize -- bash -c 'cd ~/projects/reproducible-images && echo \"=== Container Formalization Task ===\"; echo \"Running containers: acme-frontend, acme-api, acme-cron\"; echo \"Your goal: Create Dockerfiles for these manually-configured containers.\"; echo; docker ps; exec bash'" > /tmp/terminal.log 2>&1 &

sleep 5
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="