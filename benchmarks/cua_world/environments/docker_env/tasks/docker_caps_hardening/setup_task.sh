#!/bin/bash
set -e
echo "=== Setting up Docker Capabilities Hardening Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Fallback for wait_for_docker if utils not loaded
if ! type wait_for_docker &>/dev/null; then
    wait_for_docker() {
        for i in {1..60}; do
            if docker info > /dev/null 2>&1; then return 0; fi
            sleep 2
        done
        return 1
    }
fi

wait_for_docker

# 1. Clean up previous runs
echo "Cleaning up..."
docker rm -f net-monitor 2>/dev/null || true
rm -rf /home/ga/projects/net-monitor

# 2. Create Project Directory
PROJECT_DIR="/home/ga/projects/net-monitor"
mkdir -p "$PROJECT_DIR"

# 3. Create Application Code (Flask app wrapper for Ping)
cat > "$PROJECT_DIR/app.py" << 'EOF'
import subprocess
from flask import Flask, request, jsonify

app = Flask(__name__)

@app.route('/')
def home():
    return jsonify({"status": "running", "message": "Net Monitor Active"}), 200

@app.route('/ping')
def ping():
    target = request.args.get('target', '127.0.0.1')
    try:
        # Run ping -c 1. Requires NET_RAW capability or setuid root (which we don't want)
        result = subprocess.run(
            ['ping', '-c', '1', '-W', '1', target],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
        if result.returncode == 0:
            return jsonify({"target": target, "alive": True, "output": result.stdout}), 200
        else:
            return jsonify({"target": target, "alive": False, "error": result.stderr}), 500
    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    # Binding to port 80 requires root OR NET_BIND_SERVICE capability
    app.run(host='0.0.0.0', port=80)
EOF

cat > "$PROJECT_DIR/requirements.txt" << 'EOF'
flask==3.0.0
EOF

# 4. Create Initial Vulnerable Dockerfile (Runs as Root)
cat > "$PROJECT_DIR/Dockerfile" << 'EOF'
FROM python:3.11-slim

# Install ping
RUN apt-get update && apt-get install -y iputils-ping && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .

# Setup the user 'monitor' but DO NOT switch to it yet (Agent must do this)
RUN useradd -m -u 1000 monitor

# Default runs as root
CMD ["python", "app.py"]
EOF

# 5. Create Initial Docker Compose (No caps restrictions)
cat > "$PROJECT_DIR/docker-compose.yml" << 'EOF'
services:
  net-monitor:
    build: .
    container_name: net-monitor
    ports:
      - "80:80"
    # Agent needs to modify capabilities here
EOF

# Fix permissions
chown -R ga:ga "$PROJECT_DIR"

# 6. Start the initial state (Running as root)
echo "Starting initial stack..."
cd "$PROJECT_DIR"
# Force build to ensure image exists
su - ga -c "docker compose up -d --build"

# 7. Record Baseline State
echo "Waiting for service..."
sleep 5
INITIAL_UID=$(docker exec net-monitor id -u 2>/dev/null || echo "unknown")
echo "Initial UID: $INITIAL_UID"

# Record task start time
date +%s > /tmp/task_start_time.txt

# 8. Setup Terminal for Agent
su - ga -c "DISPLAY=:1 gnome-terminal --maximize -- bash -c 'cd ~/projects/net-monitor && echo \"=== Network Monitor Hardening Task ===\"; echo \"Current Status:\"; docker compose ps; echo; echo \"Check user:\"; docker exec net-monitor id; echo; exec bash'" > /tmp/terminal_launch.log 2>&1 &
sleep 2

# 9. Take Screenshot
if type take_screenshot &>/dev/null; then
    take_screenshot /tmp/task_initial.png
else
    DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true
fi

echo "=== Setup Complete ==="