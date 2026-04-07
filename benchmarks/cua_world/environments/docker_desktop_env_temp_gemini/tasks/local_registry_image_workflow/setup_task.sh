#!/bin/bash
echo "=== Setting up local_registry_image_workflow ==="

source /workspace/scripts/task_utils.sh

if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type wait_for_docker_daemon &>/dev/null; then
    wait_for_docker_daemon() {
        local timeout="${1:-60}"
        local i=0
        while [ $i -lt $timeout ]; do
            timeout 5 docker info >/dev/null 2>&1 && return 0
            sleep 2; i=$((i+2))
        done
        return 1
    }
fi

wait_for_docker_daemon 60

APP_DIR="/home/ga/api-service"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR"

# --- Python Flask API service ---
cat > "$APP_DIR/app.py" << 'PYEOF'
import os
import json
import datetime
from flask import Flask, jsonify, request

app = Flask(__name__)
VERSION = os.environ.get("APP_VERSION", "1.0.0")
SERVICE_NAME = os.environ.get("SERVICE_NAME", "api-service")

# In-memory store (simple, no external DB required)
_store = {}

@app.route('/')
def index():
    return jsonify({
        "service": SERVICE_NAME,
        "version": VERSION,
        "status": "running",
        "timestamp": datetime.datetime.utcnow().isoformat()
    })

@app.route('/health')
def health():
    return jsonify({"status": "ok", "service": SERVICE_NAME})

@app.route('/api/v1/items', methods=['GET'])
def list_items():
    return jsonify({"items": list(_store.values()), "count": len(_store)})

@app.route('/api/v1/items', methods=['POST'])
def create_item():
    data = request.get_json() or {}
    item_id = str(len(_store) + 1)
    item = {"id": item_id, "name": data.get("name", "unnamed"), "created": datetime.datetime.utcnow().isoformat()}
    _store[item_id] = item
    return jsonify(item), 201

@app.route('/api/v1/items/<item_id>', methods=['GET'])
def get_item(item_id):
    item = _store.get(item_id)
    if not item:
        return jsonify({"error": "not found"}), 404
    return jsonify(item)

if __name__ == '__main__':
    port = int(os.environ.get("PORT", 5000))
    app.run(host='0.0.0.0', port=port, debug=False)
PYEOF

cat > "$APP_DIR/requirements.txt" << 'EOF'
flask==3.0.3
gunicorn==21.2.0
EOF

cat > "$APP_DIR/Dockerfile" << 'EOF'
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

ENV PORT=5000
ENV APP_VERSION=1.0.0
ENV SERVICE_NAME=api-service

EXPOSE 5000

CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "app:app"]
EOF

# Stop and remove any previous registry or api-service containers
docker stop local-registry 2>/dev/null || true
docker rm local-registry 2>/dev/null || true
docker stop api-service 2>/dev/null || true
docker rm api-service 2>/dev/null || true

# Remove any previous local registry images of api-service
docker rmi localhost:5000/api-service:v1.0.0 localhost:5000/api-service:latest 2>/dev/null || true

# Pre-pull registry:2 so agent doesn't have to wait for download
echo "Pre-pulling registry:2..."
docker pull registry:2 2>&1 | tail -2

# Note: We do NOT start the registry or build the image — that's the agent's job

# Record initial state
echo "0" > /tmp/initial_registry_images
date +%s > /tmp/task_start_timestamp

chown -R ga:ga "$APP_DIR"
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "API service code at: $APP_DIR"
echo "registry:2 image pre-pulled"
echo "Task:"
echo "  1. Start registry:2 on port 5000"
echo "  2. Build and push localhost:5000/api-service:v1.0.0 AND :latest"
echo "  3. Create docker-compose.yml using registry image"
echo "  4. Deploy compose stack — app on port 7080"
