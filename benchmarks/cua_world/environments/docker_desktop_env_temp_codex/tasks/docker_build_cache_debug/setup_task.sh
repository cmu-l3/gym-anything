#!/bin/bash
set -e

echo "=== Setting up Docker Build Cache Debug Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Create project directory
PROJECT_DIR="/home/ga/build-project"
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR/utils" "$PROJECT_DIR/templates" "$PROJECT_DIR/tests"

# --- Create Real Application Files ---

# 1. The Broken Dockerfile
# Anti-patterns:
# - COPY . . (first) -> invalidates everything
# - pip install (after COPY)
# - apt-get (last)
cat > "$PROJECT_DIR/Dockerfile" << 'DOCKERFILE'
FROM python:3.11-slim

LABEL maintainer="devteam@example.com"
LABEL version="1.2.0"

WORKDIR /app

# BUG 1: Copies ALL source before installing dependencies
# Any change to any .py file invalidates pip install cache
COPY . .

# BUG 2: pip install after COPY . — cache busted on every code change
RUN pip install --no-cache-dir -r requirements.txt

# BUG 3: System packages installed LAST — rebuilt every time
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl wget && \
    rm -rf /var/lib/apt/lists/*

ENV FLASK_APP=app.py
ENV FLASK_ENV=production

EXPOSE 5000

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD curl -f http://localhost:5000/health || exit 1

CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "app:app"]
DOCKERFILE

# 2. requirements.txt
cat > "$PROJECT_DIR/requirements.txt" << 'REQUIREMENTS'
flask==3.0.0
requests==2.31.0
gunicorn==21.2.0
Werkzeug==3.0.1
Jinja2==3.1.2
MarkupSafe==2.1.3
itsdangerous==2.1.2
click==8.1.7
blinker==1.7.0
REQUIREMENTS

# 3. app.py (Real Flask App)
cat > "$PROJECT_DIR/app.py" << 'APPPY'
import os
from flask import Flask, jsonify, render_template

app = Flask(__name__)

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/health')
def health():
    return jsonify({"status": "healthy", "version": "1.2.0"}), 200

@app.route('/api/info')
def info():
    return jsonify({
        "app": "build-project",
        "version": "1.2.0",
        "python": os.sys.version,
        "environment": os.getenv("FLASK_ENV", "development")
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False)
APPPY

# 4. Supporting files
cat > "$PROJECT_DIR/config.py" << 'CONFIGPY'
import os
class Config:
    SECRET_KEY = os.getenv('SECRET_KEY', 'dev-secret-key')
    DEBUG = False
CONFIGPY

cat > "$PROJECT_DIR/utils/__init__.py" << 'INITPY'
# utils package
INITPY

cat > "$PROJECT_DIR/templates/index.html" << 'INDEXHTML'
<!DOCTYPE html>
<html>
<head><title>Build Project</title></head>
<body>
    <h1>Build Project v1.2.0</h1>
    <p>Flask application running in Docker.</p>
</body>
</html>
INDEXHTML

cat > "$PROJECT_DIR/README.md" << 'README'
# Build Project
This project suffers from slow builds. Please fix the Dockerfile.
README

# 5. Create "heavy" context files to justify .dockerignore
# Create a .git directory with dummy objects
mkdir -p "$PROJECT_DIR/.git/objects"
mkdir -p "$PROJECT_DIR/.git/refs"
echo "ref: refs/heads/main" > "$PROJECT_DIR/.git/HEAD"
# Create 20MB of dummy data in .git to make the context heavy
dd if=/dev/urandom of="$PROJECT_DIR/.git/objects/dummy.pack" bs=1M count=20 2>/dev/null || true

# Create __pycache__ (should be ignored)
mkdir -p "$PROJECT_DIR/__pycache__"
touch "$PROJECT_DIR/__pycache__/app.cpython-311.pyc"

# Set permissions
chown -R ga:ga "$PROJECT_DIR"

# Record initial file hash for anti-gaming (detect if file changed)
md5sum "$PROJECT_DIR/Dockerfile" > /tmp/initial_dockerfile_hash.txt

# Pre-pull the base image to speed up the valid part of the build
# (We want to test layering logic, not internet speed)
echo "Pre-pulling python:3.11-slim..."
docker pull python:3.11-slim > /dev/null 2>&1 || true

# Open VS Code or a terminal to the project directory to hint the user
# But since this is a desktop env, we'll open a file manager
su - ga -c "DISPLAY=:1 nautilus '$PROJECT_DIR' > /dev/null 2>&1 &"

# Ensure Docker Desktop is running
if ! docker_desktop_running; then
    echo "Starting Docker Desktop..."
    su - ga -c "DISPLAY=:1 XDG_RUNTIME_DIR=/run/user/1000 /opt/docker-desktop/bin/docker-desktop > /tmp/docker-desktop.log 2>&1 &"
fi

# Wait a bit for window
sleep 5

# Maximize whatever opened
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="