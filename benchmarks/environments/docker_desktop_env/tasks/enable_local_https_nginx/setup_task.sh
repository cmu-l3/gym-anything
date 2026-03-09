#!/bin/bash
# Setup script for enable_local_https_nginx
set -e

echo "=== Setting up enable_local_https_nginx task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Define paths
PROJECT_DIR="/home/ga/ssl-task"
CERTS_DIR="$PROJECT_DIR/certs"
NGINX_DIR="$PROJECT_DIR/nginx"
HTML_DIR="$PROJECT_DIR/html"

# Clean up any previous run
rm -rf "$PROJECT_DIR"
mkdir -p "$CERTS_DIR" "$NGINX_DIR" "$HTML_DIR"

# 1. Generate Self-Signed Certificates
echo "Generating self-signed certificates..."
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout "$CERTS_DIR/server.key" \
    -out "$CERTS_DIR/server.crt" \
    -subj "/C=US/ST=State/L=City/O=DevOps/OU=Local/CN=localhost" 2>/dev/null

# Calculate and save the fingerprint of the generated cert for verification
# We want the agent to use THIS specific cert, forcing them to mount it.
openssl x509 -noout -fingerprint -sha256 -in "$CERTS_DIR/server.crt" | cut -d= -f2 > /tmp/expected_cert_fingerprint.txt
echo "Expected Cert Fingerprint: $(cat /tmp/expected_cert_fingerprint.txt)"

# 2. Create HTML Content
cat > "$HTML_DIR/index.html" << 'HTML'
<!DOCTYPE html>
<html>
<head>
    <title>Secure Local Site</title>
</head>
<body>
    <h1>Welcome to the Secure Local Site</h1>
    <p>If you see this over HTTPS, the task is complete!</p>
</body>
</html>
HTML

# 3. Create Initial Nginx Config (HTTP only)
cat > "$NGINX_DIR/default.conf" << 'CONF'
server {
    listen 80;
    server_name localhost;

    location / {
        root   /usr/share/nginx/html;
        index  index.html index.htm;
    }
}
CONF

# 4. Create Initial Docker Compose (HTTP only)
cat > "$PROJECT_DIR/docker-compose.yml" << 'YAML'
services:
  web-server:
    image: nginx:alpine
    container_name: web-server
    ports:
      - "8080:80"
    volumes:
      - ./html:/usr/share/nginx/html:ro
      - ./nginx/default.conf:/etc/nginx/conf.d/default.conf:ro
    restart: unless-stopped
YAML

# Set permissions
chown -R ga:ga "$PROJECT_DIR"

# 5. Start the initial environment
echo "Starting initial environment..."
cd "$PROJECT_DIR"
su - ga -c "cd $PROJECT_DIR && docker compose up -d"

# Wait for container to be healthy
sleep 5
if curl -s http://localhost:8080 | grep -q "Secure Local Site"; then
    echo "Initial HTTP setup verified."
else
    echo "WARNING: Initial HTTP setup failed."
fi

# Record task start time
date +%s > /tmp/task_start_time.txt

# Open VS Code or a terminal for the agent? 
# Let's open the project folder in a file manager or terminal to be helpful.
su - ga -c "DISPLAY=:1 xdg-open $PROJECT_DIR" &
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="