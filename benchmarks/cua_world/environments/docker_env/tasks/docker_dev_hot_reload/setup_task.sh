#!/bin/bash
set -e
echo "=== Setting up Task: Docker Dev Hot-Reload ==="

# Define paths
PROJECT_DIR="/home/ga/projects/inventory-service"
mkdir -p "$PROJECT_DIR/app"

# 1. Create Python Flask Application
cat > "$PROJECT_DIR/app/main.py" << 'EOF'
from flask import Flask, jsonify
import os

app = Flask(__name__)

@app.route("/")
def home():
    return jsonify({
        "service": "Inventory API",
        "status": "active",
        "version": "1.0.0",
        "message": "Production Instance"
    })

if __name__ == "__main__":
    # Note: In production this file is run via gunicorn, not directly
    app.run(host="0.0.0.0", port=5000)
EOF

# 2. Create Dockerfile (Production Ready - intentionally uses gunicorn)
cat > "$PROJECT_DIR/Dockerfile" << 'EOF'
FROM python:3.11-slim

WORKDIR /app

# Install dependencies
RUN pip install flask gunicorn

# Copy application code
COPY app/ /app/

# Run as non-root user for security
RUN useradd -m appuser && chown -R appuser:appuser /app
USER appuser

# Default production command
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "main:app"]
EOF

# 3. Create Immutable docker-compose.yml
cat > "$PROJECT_DIR/docker-compose.yml" << 'EOF'
services:
  inventory-api:
    build: .
    image: inventory-api:latest
    # Production constraints:
    # - No ports exposed (internal only)
    # - Read-only root filesystem to prevent runtime changes
    read_only: false
    environment:
      - FLASK_APP=main.py
      - ENVIRONMENT=production
    restart: always
EOF

# Set ownership
chown -R ga:ga "$PROJECT_DIR"

# Pre-build the image to save time for the agent
# (This ensures the "production" image exists)
echo "Pre-building base image..."
cd "$PROJECT_DIR"
su - ga -c "docker compose build"

# Record checksum of docker-compose.yml for verification (Immutability check)
md5sum "$PROJECT_DIR/docker-compose.yml" | awk '{print $1}' > /tmp/original_compose_checksum.txt

# Record task start time
date +%s > /tmp/task_start_time.txt

# Open a terminal for the agent with instructions
su - ga -c "DISPLAY=:1 gnome-terminal --maximize -- bash -c 'cd ~/projects/inventory-service && echo \"Task: Enable Hot-Reload for Inventory API\"; echo \"1. Create docker-compose.override.yml\"; echo \"2. Mount ./app to /app\"; echo \"3. Expose port 5000\"; echo \"4. Set FLASK_DEBUG=1\"; echo \"5. Run: docker compose up -d\"; echo; ls -la; exec bash'" > /tmp/terminal_launch.log 2>&1 &

# Take initial screenshot
source /workspace/scripts/task_utils.sh 2>/dev/null || true
if type take_screenshot &>/dev/null; then
    take_screenshot /tmp/task_initial.png
else
    DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true
fi

echo "=== Setup Complete ==="