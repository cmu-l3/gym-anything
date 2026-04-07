#!/bin/bash
# Setup script for docker_entrypoint_debug task
# Creates 4 services with specific entrypoint bugs:
# 1. acme-cache-warmer: Bash syntax in Alpine (/bin/sh)
# 2. acme-event-processor: CRLF line endings
# 3. acme-report-generator: set -e with failing grep
# 4. acme-static-server: Wrong file path sourced

set -e
echo "=== Setting up Docker Entrypoint Debug Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Wait for Docker
if ! type wait_for_docker &>/dev/null; then
    wait_for_docker() {
        for i in {1..60}; do
            if docker info > /dev/null 2>&1; then return 0; fi
            sleep 2
        done; return 1
    }
fi
wait_for_docker

# Cleanup previous
docker rm -f acme-cache-warmer acme-event-processor acme-report-generator acme-static-server 2>/dev/null || true

BASE_DIR="/home/ga/projects/acme-services"
mkdir -p "$BASE_DIR"

# ==============================================================================
# Service 1: acme-cache-warmer (Bash syntax in Alpine)
# ==============================================================================
echo "Setting up acme-cache-warmer..."
S1_DIR="$BASE_DIR/cache-warmer"
mkdir -p "$S1_DIR"

cat > "$S1_DIR/app.sh" << 'EOF'
#!/bin/sh
echo "Cache warmer started..."
while true; do sleep 60; done
EOF
chmod +x "$S1_DIR/app.sh"

cat > "$S1_DIR/entrypoint.sh" << 'EOF'
#!/bin/bash
# Check if we are in prod
ENV_TYPE="prod"

# Bash-specific syntax: [[ ]] and array
if [[ "$ENV_TYPE" == "prod" ]]; then
    echo "Production mode initialized"
fi

MODES=("fast" "safe")
echo "Mode: ${MODES[0]}"

exec "$@"
EOF
chmod +x "$S1_DIR/entrypoint.sh"

cat > "$S1_DIR/Dockerfile" << 'EOF'
FROM alpine:3.18
WORKDIR /app
COPY app.sh .
COPY entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh
ENTRYPOINT ["entrypoint.sh"]
CMD ["./app.sh"]
EOF

# ==============================================================================
# Service 2: acme-event-processor (Windows CRLF line endings)
# ==============================================================================
echo "Setting up acme-event-processor..."
S2_DIR="$BASE_DIR/event-processor"
mkdir -p "$S2_DIR"

cat > "$S2_DIR/package.json" << 'EOF'
{
  "name": "event-processor",
  "version": "1.0.0",
  "main": "index.js",
  "scripts": { "start": "node index.js" }
}
EOF

cat > "$S2_DIR/index.js" << 'EOF'
console.log('Event processor worker started');
setInterval(() => { console.log('Processing...'); }, 5000);
EOF

cat > "$S2_DIR/entrypoint.sh" << 'EOF'
#!/bin/sh
echo "Initializing node environment..."
exec "$@"
EOF
# Convert to CRLF to cause failure
unix2dos "$S2_DIR/entrypoint.sh" 2>/dev/null || sed -i 's/$/\r/' "$S2_DIR/entrypoint.sh"
chmod +x "$S2_DIR/entrypoint.sh"

cat > "$S2_DIR/Dockerfile" << 'EOF'
FROM node:20-slim
WORKDIR /app
COPY package.json index.js ./
COPY entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh
ENTRYPOINT ["entrypoint.sh"]
CMD ["npm", "start"]
EOF

# ==============================================================================
# Service 3: acme-report-generator (set -e killing script)
# ==============================================================================
echo "Setting up acme-report-generator..."
S3_DIR="$BASE_DIR/report-generator"
mkdir -p "$S3_DIR"

cat > "$S3_DIR/app.py" << 'EOF'
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"Report Generator Healthy")

print("Starting Report Generator API on port 8000...")
HTTPServer(('0.0.0.0', 8000), Handler).serve_forever()
EOF

cat > "$S3_DIR/config.conf" << 'EOF'
DEBUG=false
DB_HOST=localhost
EOF

cat > "$S3_DIR/entrypoint.sh" << 'EOF'
#!/bin/sh
set -e

echo "Checking configuration..."

# This grep fails (returns 1) because "SPECIAL_FEATURE" is not in config.conf
# Because of set -e, the script exits immediately here.
FEATURE_ENABLED=$(grep "SPECIAL_FEATURE" config.conf)

if [ -n "$FEATURE_ENABLED" ]; then
    echo "Feature enabled"
fi

echo "Starting application..."
exec "$@"
EOF
chmod +x "$S3_DIR/entrypoint.sh"

cat > "$S3_DIR/Dockerfile" << 'EOF'
FROM python:3.11-slim
WORKDIR /app
COPY app.py config.conf ./
COPY entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh
ENTRYPOINT ["entrypoint.sh"]
CMD ["python", "app.py"]
EOF

# ==============================================================================
# Service 4: acme-static-server (Wrong config path)
# ==============================================================================
echo "Setting up acme-static-server..."
S4_DIR="$BASE_DIR/static-server"
mkdir -p "$S4_DIR"

mkdir -p "$S4_DIR/html"
echo "<h1>Acme Static Server</h1>" > "$S4_DIR/html/index.html"

cat > "$S4_DIR/env.conf" << 'EOF'
export ENVIRONMENT=production
EOF

cat > "$S4_DIR/entrypoint.sh" << 'EOF'
#!/bin/sh
# Attempt to load environment config
# BUG: Dockerfile puts it at /etc/nginx/env.conf, not conf.d
source /etc/nginx/conf.d/env.conf

echo "Starting Nginx in $ENVIRONMENT mode..."
exec "$@"
EOF
chmod +x "$S4_DIR/entrypoint.sh"

cat > "$S4_DIR/Dockerfile" << 'EOF'
FROM nginx:1.24-alpine
COPY html /usr/share/nginx/html
# NOTE: File copied to root nginx dir, not conf.d
COPY env.conf /etc/nginx/env.conf
COPY entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh
ENTRYPOINT ["entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
EOF

# ==============================================================================
# Build and Run (Fail)
# ==============================================================================
chown -R ga:ga "$BASE_DIR"

echo "Building buggy images..."
cd "$S1_DIR" && docker build -t acme-cache-warmer:latest .
cd "$S2_DIR" && docker build -t acme-event-processor:latest .
cd "$S3_DIR" && docker build -t acme-report-generator:latest .
cd "$S4_DIR" && docker build -t acme-static-server:latest .

echo "Starting containers (expecting failures)..."
# We start them detached; they will exit immediately.
docker run -d --name acme-cache-warmer acme-cache-warmer:latest || true
docker run -d --name acme-event-processor acme-event-processor:latest || true
docker run -d -p 8000:8000 --name acme-report-generator acme-report-generator:latest || true
docker run -d -p 8080:80 --name acme-static-server acme-static-server:latest || true

sleep 2

echo "Initial container states (should be Exited):"
docker ps -a --format "table {{.Names}}\t{{.Status}}" | grep acme

# Timestamp for verification
date +%s > /tmp/task_start_time.txt

# Create Desktop dir
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# Terminal
su - ga -c "DISPLAY=:1 gnome-terminal --maximize -- bash -c 'cd ~/projects/acme-services; echo \"Docker Entrypoint Debugging Task\"; echo; echo \"Current Status:\"; docker ps -a --format \"table {{.Names}}\t{{.Status}}\" | grep acme; echo; echo \"Check logs: docker logs <container>\"; exec bash'" > /tmp/terminal.log 2>&1 &

# Screenshot
if type take_screenshot &>/dev/null; then
    take_screenshot /tmp/task_initial.png
else
    DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true
fi

echo "=== Setup Complete ==="