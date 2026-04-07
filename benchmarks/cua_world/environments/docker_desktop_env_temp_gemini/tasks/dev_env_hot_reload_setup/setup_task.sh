#!/bin/bash
set -e
echo "=== Setting up Hot Reload Development Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Docker Desktop is running
if ! docker_desktop_running; then
    echo "Starting Docker Desktop..."
    su - ga -c "DISPLAY=:1 XDG_RUNTIME_DIR=/run/user/1000 /opt/docker-desktop/bin/docker-desktop > /tmp/docker-desktop.log 2>&1 &"
    wait_for_docker_daemon 60
fi

# Project setup
PROJECT_DIR="/home/ga/projects/quote-service"
mkdir -p "$PROJECT_DIR/src"
mkdir -p "$PROJECT_DIR/src/templates"

# Create Flask Application
cat > "$PROJECT_DIR/src/app.py" << 'PYEOF'
from flask import Flask, render_template_string
import os

app = Flask(__name__)

@app.route('/')
def hello():
    # Simple template
    html = """
    <!DOCTYPE html>
    <html>
    <head><title>Quote Service</title></head>
    <body style="font-family: sans-serif; text-align: center; padding: 50px;">
        <h1>Quote Service</h1>
        <p style="font-size: 24px; color: #333;">{{ message }}</p>
        <hr>
        <p>Running on: {{ env }}</p>
    </body>
    </html>
    """
    return render_template_string(html, message="Static Version 1.0", env=os.environ.get("FLASK_ENV", "production"))

if __name__ == '__main__':
    # Production entry point
    app.run(host='0.0.0.0', port=5000)
PYEOF

# Create Requirements
cat > "$PROJECT_DIR/requirements.txt" << 'EOF'
flask==3.0.0
gunicorn==21.2.0
EOF

# Create Dockerfile (Production optimized)
cat > "$PROJECT_DIR/Dockerfile" << 'DOCKERFILE'
FROM python:3.9-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy source code (this makes the image static)
COPY src/ .

# Production command
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "app:app"]
DOCKERFILE

# Create initial docker-compose.yml (Static, no hot reload)
cat > "$PROJECT_DIR/docker-compose.yml" << 'YAML'
services:
  web:
    build: .
    ports:
      - "5000:5000"
    # User needs to add volumes and command override here
YAML

# Fix permissions
chown -R ga:ga "/home/ga/projects"

# Pre-build the image to save time for the user, but don't start it yet
# This ensures the 'static' version is cached
echo "Pre-building base image..."
cd "$PROJECT_DIR"
su - ga -c "docker compose build"

# Open the project folder in file manager
su - ga -c "DISPLAY=:1 nautilus '$PROJECT_DIR' &"
sleep 2

# Open VS Code (if available) or Text Editor to the project
if command -v code >/dev/null; then
    su - ga -c "DISPLAY=:1 code '$PROJECT_DIR'"
else
    su - ga -c "DISPLAY=:1 gedit '$PROJECT_DIR/docker-compose.yml' &"
fi

# Maximize windows
sleep 2
WID=$(DISPLAY=:1 wmctrl -l | grep -i "code\|text\|file" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="