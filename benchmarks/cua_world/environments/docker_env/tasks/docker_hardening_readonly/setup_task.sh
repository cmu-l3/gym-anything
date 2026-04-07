#!/bin/bash
# Setup script for docker_hardening_readonly task
# Creates a vulnerable web service that writes to local disk, requiring hardening.

set -e
echo "=== Setting up Docker Hardening Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type wait_for_docker &>/dev/null; then
    wait_for_docker() {
        for i in {1..60}; do
            if docker info > /dev/null 2>&1; then return 0; fi
            sleep 2
        done; return 1
    }
fi
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

wait_for_docker

# 1. Create Project Directory
PROJECT_DIR="/home/ga/projects/acme-ingest"
mkdir -p "$PROJECT_DIR/app"

# 2. Create the Application (Python)
# This app attempts to write to 3 locations on startup.
cat > "$PROJECT_DIR/app/main.py" << 'EOF'
import http.server
import socketserver
import os
import time
import sys
import threading

# Configuration
PID_FILE = "/run/acme/app.pid"
CACHE_DIR = "/var/lib/acme/cache"
LOG_FILE = "/var/log/acme/server.log"
PORT = 8080

def write_pid():
    print(f"Writing PID to {PID_FILE}...")
    try:
        with open(PID_FILE, "w") as f:
            f.write(str(os.getpid()))
    except OSError as e:
        print(f"CRITICAL: Failed to write PID file: {e}")
        sys.exit(1)

def write_cache():
    print(f"Writing cache data to {CACHE_DIR}...")
    try:
        if not os.path.exists(CACHE_DIR):
            print(f"Cache dir {CACHE_DIR} does not exist!")
            sys.exit(1)
        with open(os.path.join(CACHE_DIR, "startup.dat"), "w") as f:
            f.write(f"Cache initialized at {time.time()}")
    except OSError as e:
        print(f"CRITICAL: Failed to write cache: {e}")
        sys.exit(1)

def write_log(msg):
    print(f"Logging: {msg}")
    try:
        with open(LOG_FILE, "a") as f:
            f.write(f"{time.ctime()}: {msg}\n")
    except OSError as e:
        print(f"CRITICAL: Failed to write log: {e}")
        sys.exit(1)

class HealthHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(b'{"status": "ok", "readonly_compatible": "maybe"}')
            # Attempt a runtime write to log to prove persistence
            try:
                write_log("Health check received")
            except:
                pass # Don't crash on health check, just log failure to stdout
        else:
            self.send_response(404)
            self.end_headers()

def main():
    print("Starting Acme Ingest Service...")
    
    # These will FAIL if read-only filesystem is on and mounts are missing
    write_pid()
    write_cache()
    write_log("Service started successfully")
    
    # Start HTTP server
    with socketserver.TCPServer(("", PORT), HealthHandler) as httpd:
        print(f"Serving on port {PORT}")
        httpd.serve_forever()

if __name__ == "__main__":
    main()
EOF

# 3. Create Dockerfile
# We pre-create the directories so they exist in the image. 
# If they didn't exist, read-only root would prevent even mounting (if using --tmpfs without mkdir) 
# or just general confusion.
cat > "$PROJECT_DIR/Dockerfile" << 'EOF'
FROM python:3.11-slim

WORKDIR /app

# Create necessary directories
RUN mkdir -p /run/acme \
    && mkdir -p /var/lib/acme/cache \
    && mkdir -p /var/log/acme

# Install curl for healthcheck debugging (optional)
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

COPY app/ .

CMD ["python", "-u", "main.py"]
EOF

# 4. Create insecure docker-compose.yml
# This works by default because root is writable.
cat > "$PROJECT_DIR/docker-compose.yml" << 'EOF'
services:
  acme-ingest:
    build: .
    container_name: acme-ingest
    ports:
      - "8080:8080"
    # SECURITY TODO: Enable read-only root filesystem
    # read_only: true
EOF

chown -R ga:ga "$PROJECT_DIR"

# 5. Build and Start the initial insecure version
echo "Building and starting initial state..."
cd "$PROJECT_DIR"
# Stop any existing
docker compose down -v 2>/dev/null || true
# Start
sudo -u ga docker compose up -d --build

# Wait for it to be ready
echo "Waiting for service to start..."
for i in {1..30}; do
    if curl -s http://localhost:8080/health >/dev/null; then
        echo "Service is up (insecure mode)."
        break
    fi
    sleep 1
done

# Record setup timestamp
date +%s > /tmp/task_start_timestamp

# Create Desktop directory
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# Open terminal for user
su - ga -c "DISPLAY=:1 gnome-terminal --maximize -- bash -c 'cd ~/projects/acme-ingest && echo \"Acme Ingest Service Hardening Task\"; echo; echo \"Current status:\"; docker compose ps; echo; echo \"The security team requires you to enable read_only: true in docker-compose.yml\"; echo \"But the app writes to specific paths you must identify and handle.\"; echo; exec bash'" > /tmp/hardening_terminal.log 2>&1 &
sleep 3

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Project Dir: $PROJECT_DIR"
echo "Service: acme-ingest running (insecure)"