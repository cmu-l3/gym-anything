#!/bin/bash
# Setup script for docker_runtime_config task

set -e
echo "=== Setting up Docker Runtime Config Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Wait for Docker to be ready
wait_for_docker

# Clean up previous runs
docker rm -f acme-dashboard-test verify-run 2>/dev/null || true
docker rmi -f acme-dashboard:legacy acme-dashboard:dynamic 2>/dev/null || true
rm -rf /home/ga/projects/acme-dashboard

# Create project directory
PROJECT_DIR="/home/ga/projects/acme-dashboard"
mkdir -p "$PROJECT_DIR/app"
mkdir -p "$PROJECT_DIR/nginx"
chown -R ga:ga "$PROJECT_DIR"

# 1. Create Source Files
# config.js (Hardcoded)
cat > "$PROJECT_DIR/app/config.js" <<EOF
window.config = {
    apiUrl: "http://localhost:3000",
    featureFlags: {
        enableNewUI: true
    }
};
EOF

# index.html (Dummy)
cat > "$PROJECT_DIR/app/index.html" <<EOF
<!DOCTYPE html>
<html>
<head><title>Acme Dashboard</title></head>
<body>
<h1>Loading...</h1>
<script src="config.js"></script>
</body>
</html>
EOF

# nginx.conf (Hardcoded)
# Using full nginx.conf structure to include worker_processes
cat > "$PROJECT_DIR/nginx/nginx.conf" <<EOF
worker_processes 1;

events {
    worker_connections 1024;
}

http {
    include       mime.types;
    default_type  application/octet-stream;

    server {
        listen 80;
        server_name localhost;

        location / {
            root   /usr/share/nginx/html;
            index  index.html index.htm;
            try_files \$uri \$uri/ /index.html;
        }

        # API Proxy (Example of using other variables)
        location /api/ {
            proxy_pass http://backend:8080;
            proxy_set_header Host \$host;
        }
    }
}
EOF

# Dockerfile (Legacy)
cat > "$PROJECT_DIR/Dockerfile" <<EOF
FROM nginx:1.24-alpine

# Copy static assets
COPY app/ /usr/share/nginx/html/

# Copy nginx config
COPY nginx/nginx.conf /etc/nginx/nginx.conf

# Expose port
EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
EOF

chown -R ga:ga "$PROJECT_DIR"

# 2. Build Legacy Image
echo "Building legacy image..."
docker build -t acme-dashboard:legacy "$PROJECT_DIR"

# 3. Setup Agent Environment
date +%s > /tmp/task_start_time.txt

# Open terminal
su - ga -c "DISPLAY=:1 gnome-terminal --maximize -- bash -c 'cd ~/projects/acme-dashboard && echo \"Docker Runtime Config Task\"; echo; echo \"Current legacy setup:\"; ls -R; echo; echo \"Goal: Refactor to allow runtime injection of API_URL and WORKER_PROCESSES\"; exec bash'" > /tmp/task_terminal.log 2>&1 &
sleep 3

take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="