#!/bin/bash
set -e
echo "=== Setting up Sidecar Packet Capture Security Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Wait for Docker Daemon
wait_for_docker_daemon 120

# 2. Prepare Project Directory
PROJECT_DIR="/home/ga/debug-auth"
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR/captures"
mkdir -p "$PROJECT_DIR/app"
chown -R ga:ga "$PROJECT_DIR"

# 3. Create Dummy Auth Service (Flask)
cat > "$PROJECT_DIR/app/app.py" << 'EOF'
from flask import Flask, jsonify
import time
import random

app = Flask(__name__)

@app.route('/login', methods=['POST'])
def login():
    # Simulate work
    time.sleep(random.random() * 0.1)
    return jsonify({"status": "success", "token": "debug-token"}), 200

@app.route('/health')
def health():
    return jsonify({"status": "healthy"}), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

cat > "$PROJECT_DIR/app/requirements.txt" << 'EOF'
flask==3.0.0
EOF

cat > "$PROJECT_DIR/app/Dockerfile" << 'EOF'
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
CMD ["python", "app.py"]
EOF

# 4. Create Traffic Generator Script
cat > "$PROJECT_DIR/traffic_gen.sh" << 'EOF'
#!/bin/sh
apk add --no-cache curl
while true; do
    echo "Sending request..."
    curl -s -X POST http://auth-service:5000/login > /dev/null
    sleep 2
done
EOF
chmod +x "$PROJECT_DIR/traffic_gen.sh"

# 5. Create Initial Docker Compose (Missing Sniffer)
cat > "$PROJECT_DIR/docker-compose.yml" << 'EOF'
services:
  auth-service:
    build: ./app
    container_name: auth-service
    ports:
      - "5000:5000"
    restart: always

  traffic-gen:
    image: alpine:latest
    container_name: traffic-gen
    volumes:
      - ./traffic_gen.sh:/traffic_gen.sh
    command: /traffic_gen.sh
    depends_on:
      - auth-service
    restart: always
EOF

# Set ownership
chown -R ga:ga "$PROJECT_DIR"

# 6. Pre-pull images and start initial stack
echo "Pre-pulling images..."
docker pull python:3.11-slim
docker pull alpine:latest

echo "Starting initial stack..."
cd "$PROJECT_DIR"
su - ga -c "cd $PROJECT_DIR && docker compose up -d --build"

# Record start time
date +%s > /tmp/task_start_time.txt

# Record initial container count
get_container_count > /tmp/initial_container_count.txt

# Ensure Docker Desktop is focused
focus_docker_desktop

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="