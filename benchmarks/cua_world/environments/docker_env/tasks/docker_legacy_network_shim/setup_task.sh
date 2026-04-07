#!/bin/bash
# Setup script for docker_legacy_network_shim
set -e

echo "=== Setting up Docker Legacy Network Shim Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

wait_for_docker

# 1. Clean up previous runs
echo "Cleaning up..."
PROJECT_DIR="/home/ga/projects/fincore-migration"
if [ -d "$PROJECT_DIR" ]; then
    cd "$PROJECT_DIR"
    docker compose down -v 2>/dev/null || true
    cd /home/ga
    rm -rf "$PROJECT_DIR"
fi

# 2. Create Project Structure
mkdir -p "$PROJECT_DIR/app"
mkdir -p "$PROJECT_DIR/logs"

# 3. Create the "Black Box" Legacy Application
# This script simulates a binary that checks for specific network conditions and filesystem paths
cat > "$PROJECT_DIR/app/main.py" << 'EOF'
import time
import socket
import os
import sys

# Configuration (Hardcoded in legacy binary)
DB_HOST = "db-primary.corp.local"
AUTH_HOST = "auth-gateway.partner.net"
LOG_DIR = "/var/log/fincore"
LOG_FILE = os.path.join(LOG_DIR, "startup_success.log")

def log(msg):
    print(f"[FinCore] {msg}", flush=True)

def check_network(hostname, port=80):
    log(f"Attempting connection to {hostname}:{port}...")
    try:
        # Resolve first to verify DNS
        ip = socket.gethostbyname(hostname)
        log(f"  Resolved {hostname} to {ip}")
        # Try connect (simulated)
        return True
    except socket.gaierror:
        log(f"  CRITICAL ERROR: Could not resolve hostname '{hostname}'.")
        return False
    except Exception as e:
        log(f"  Connection failed: {e}")
        return False

def main():
    log("Starting FinCore Legacy Engine v4.2...")
    
    # 1. Check Environment
    mode = os.environ.get("MODE", "UNKNOWN")
    log(f"Environment MODE: {mode}")
    if mode != "PRODUCTION":
        log("CRITICAL ERROR: Application expects MODE=PRODUCTION. Aborting.")
        sys.exit(1)

    # 2. Check Network Dependencies
    # Wait loop to allow sidecars to start
    connected = False
    for i in range(10):
        if check_network(DB_HOST, 5432) and check_network(AUTH_HOST, 80):
            connected = True
            break
        log("Retrying network checks in 2s...")
        time.sleep(2)
    
    if not connected:
        log("CRITICAL ERROR: Dependency services unreachable. Aborting.")
        sys.exit(1)

    # 3. Check Persistence
    if not os.path.exists(LOG_DIR):
        log(f"CRITICAL ERROR: Log directory {LOG_DIR} does not exist.")
        sys.exit(1)

    # Write success file
    try:
        with open(LOG_FILE, "w") as f:
            f.write("SYSTEM_READY\n")
            f.write(f"Timestamp: {time.time()}\n")
        log(f"Startup complete. Status written to {LOG_FILE}")
    except PermissionError:
        log(f"CRITICAL ERROR: Cannot write to {LOG_FILE}. Check permissions.")
        sys.exit(1)

    # Keep running
    while True:
        time.sleep(3600)

if __name__ == "__main__":
    main()
EOF

# 4. Create Dockerfile
cat > "$PROJECT_DIR/app/Dockerfile" << 'EOF'
FROM python:3.9-slim
WORKDIR /app
COPY main.py .
# Create log dir but don't persist it in image
RUN mkdir -p /var/log/fincore
CMD ["python", "-u", "main.py"]
EOF

# 5. Create Broken docker-compose.yml
cat > "$PROJECT_DIR/docker-compose.yml" << 'EOF'
version: '3.8'

services:
  fincore-app:
    build: ./app
    environment:
      - MODE=MIGRATION  # Wrong mode
    depends_on:
      - db
      - auth-mock
    # Missing: Volume mount for /var/log/fincore

  db:
    image: postgres:14
    environment:
      POSTGRES_PASSWORD: password
    # Missing: Network alias for db-primary.corp.local

  auth-mock:
    image: nginx:alpine
    # Missing: Network alias for auth-gateway.partner.net

EOF

# 6. Set permissions
chown -R ga:ga "$PROJECT_DIR"

# 7. Record Baseline State
# Calculate MD5 of main.py to prevent cheating (modifying the app instead of infrastructure)
md5sum "$PROJECT_DIR/app/main.py" | awk '{print $1}' > /tmp/main_py_checksum.txt

# Record task start time
date +%s > /tmp/task_start_time.txt

# 8. Setup User Environment
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# Launch terminal
su - ga -c "DISPLAY=:1 gnome-terminal --maximize -- bash -c 'cd ~/projects/fincore-migration && echo \"FinCore Migration Task\"; echo \"---------------------\"; echo \"Legacy App requires:\"; echo \" 1. Connection to db-primary.corp.local\"; echo \" 2. Connection to auth-gateway.partner.net\"; echo \" 3. MODE=PRODUCTION\"; echo \" 4. Persistent logs at /var/log/fincore\"; echo; echo \"Current Status: Application crashing.\"; echo \"Fix docker-compose.yml to resolve issues.\"; exec bash'" > /tmp/terminal_launch.log 2>&1 &

sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="