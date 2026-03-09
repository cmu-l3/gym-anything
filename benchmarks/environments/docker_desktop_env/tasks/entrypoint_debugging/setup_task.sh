#!/bin/bash
# Setup script for entrypoint_debugging task
# Creates a broken Docker Compose project that the agent must fix

set -e
echo "=== Setting up entrypoint_debugging task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Directory setup
PROJECT_DIR="/home/ga/entrypoint-debug"
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR/gateway" "$PROJECT_DIR/api" "$PROJECT_DIR/worker"

# ------------------------------------------------------------------
# 1. GATEWAY SERVICE (Nginx)
# Bug: entrypoint.sh is not executable in the image
# ------------------------------------------------------------------

# Correct entrypoint script (uses envsubst)
cat > "$PROJECT_DIR/gateway/entrypoint.sh" << 'EOF'
#!/bin/sh
set -e
# Template nginx config with environment variables
envsubst '${API_HOST} ${API_PORT}' < /etc/nginx/conf.d/default.conf.template > /etc/nginx/conf.d/default.conf
exec "$@"
EOF

# Nginx config template
cat > "$PROJECT_DIR/gateway/nginx.conf.template" << 'EOF'
server {
    listen 80;
    location / {
        proxy_pass http://${API_HOST}:${API_PORT};
    }
}
EOF

# Buggy Dockerfile (missing chmod +x on entrypoint)
cat > "$PROJECT_DIR/gateway/Dockerfile" << 'EOF'
FROM nginx:alpine
COPY nginx.conf.template /etc/nginx/conf.d/default.conf.template
COPY entrypoint.sh /entrypoint.sh
# BUG: Missing chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
EOF

# ------------------------------------------------------------------
# 2. API SERVICE (Flask)
# Bug: Dockerfile uses ENTRYPOINT ["python", "app.py"] which ignores CMD args
# The app requires env vars, but compose passes CLI args.
# ------------------------------------------------------------------

# Python App (reads ENV vars, ignores CLI args unless parsed)
cat > "$PROJECT_DIR/api/app.py" << 'PYEOF'
import os
import sys
from flask import Flask, jsonify

app = Flask(__name__)

@app.route('/health')
def health():
    return jsonify({"status": "ok", "service": "api"})

@app.route('/')
def root():
    return jsonify({"message": "Hello from API"})

if __name__ == '__main__':
    # Default to localhost if not set (this causes the bind issue inside container)
    host = os.environ.get('HOST', '127.0.0.1') 
    port = int(os.environ.get('PORT', 5000))
    print(f"Starting API on {host}:{port}")
    app.run(host=host, port=port)
PYEOF

# Helper entrypoint (The fix is to use this, or change Dockerfile to pass CMD to ENTRYPOINT)
cat > "$PROJECT_DIR/api/entrypoint.sh" << 'EOF'
#!/bin/sh
# Helper script to parse CLI args into ENV vars
while [ "$#" -gt 0 ]; do
  case "$1" in
    --host) HOST="$2"; shift 2;;
    --port) PORT="$2"; shift 2;;
    *) shift 1;;
  esac
done
export HOST
export PORT
exec python app.py
EOF
chmod +x "$PROJECT_DIR/api/entrypoint.sh"

cat > "$PROJECT_DIR/api/requirements.txt" << 'EOF'
flask
EOF

# Buggy Dockerfile (ENTRYPOINT exec form consumes CMD args, doesn't pass them to python correctly to parse, 
# and app.py doesn't parse them anyway. It ignores the command from compose)
cat > "$PROJECT_DIR/api/Dockerfile" << 'EOF'
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
COPY entrypoint.sh .
# BUG: This runs python app.py directly. The arguments from compose 
# ("--host 0.0.0.0") are passed to python, but app.py doesn't look at sys.argv.
# It falls back to defaults (127.0.0.1), making it unreachable.
ENTRYPOINT ["python", "app.py"]
EOF

# ------------------------------------------------------------------
# 3. WORKER SERVICE (Shell script)
# Bug: Shell form ENTRYPOINT ignores CMD arguments
# ------------------------------------------------------------------

# Job script
cat > "$PROJECT_DIR/worker/job.sh" << 'EOF'
#!/bin/sh
INTERVAL=${INTERVAL:-60} # Default to 60s if not set
echo "Starting worker with interval=${INTERVAL}s"
while true; do
    echo "Processing job... (interval=${INTERVAL})"
    sleep "$INTERVAL"
done
EOF
chmod +x "$PROJECT_DIR/worker/job.sh"

# Entrypoint that parses args
cat > "$PROJECT_DIR/worker/entrypoint.sh" << 'EOF'
#!/bin/sh
# Parse arguments
while [ "$#" -gt 0 ]; do
  case "$1" in
    --interval) export INTERVAL="$2"; shift 2;;
    *) shift 1;;
  esac
done
exec ./job.sh
EOF
chmod +x "$PROJECT_DIR/worker/entrypoint.sh"

# Buggy Dockerfile (Shell form ENTRYPOINT)
cat > "$PROJECT_DIR/worker/Dockerfile" << 'EOF'
FROM alpine:latest
WORKDIR /app
COPY job.sh .
COPY entrypoint.sh .
# BUG: Shell form ignores CMD arguments from docker-compose
ENTRYPOINT ./entrypoint.sh
EOF

# ------------------------------------------------------------------
# DOCKER COMPOSE FILE
# ------------------------------------------------------------------

cat > "$PROJECT_DIR/docker-compose.yml" << 'EOF'
services:
  gateway:
    build: ./gateway
    ports:
      - "8080:80"
    environment:
      - API_HOST=api
      - API_PORT=5000
    depends_on:
      - api

  api:
    build: ./api
    ports:
      - "5000:5000"
    # These args are currently ignored by the API container due to the bug
    command: ["--host", "0.0.0.0", "--port", "5000"]

  worker:
    build: ./worker
    # This arg is currently ignored by the Worker container due to the bug
    command: ["--interval", "5"]
EOF

# Set ownership
chown -R ga:ga "$PROJECT_DIR"

# Pre-pull images to speed up task
echo "Pre-pulling base images..."
docker pull nginx:alpine &
docker pull python:3.11-slim &
docker pull alpine:latest &
wait

# Ensure Docker Desktop is running
echo "Checking Docker Desktop..."
if ! docker_desktop_running; then
    su - ga -c "DISPLAY=:1 XDG_RUNTIME_DIR=/run/user/1000 /opt/docker-desktop/bin/docker-desktop > /tmp/docker-desktop.log 2>&1 &"
fi
wait_for_docker_daemon 60

# Record task start time
date +%s > /tmp/task_start_time.txt

# Record initial file timestamps
stat -c %Y "$PROJECT_DIR/gateway/Dockerfile" > /tmp/initial_gateway_dockerfile_mtime
stat -c %Y "$PROJECT_DIR/api/Dockerfile" > /tmp/initial_api_dockerfile_mtime
stat -c %Y "$PROJECT_DIR/worker/Dockerfile" > /tmp/initial_worker_dockerfile_mtime

# Maximize Docker Desktop
focus_docker_desktop
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="