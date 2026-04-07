#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up legacy_app_network_aliases task ==="
date +%s > /tmp/task_start_time.txt

# Create project directory
PROJECT_DIR="/home/ga/legacy-migration"
mkdir -p "$PROJECT_DIR/app-src"

# Create Legacy App Python Script
# This script simulates the legacy app with hardcoded dependencies
cat > "$PROJECT_DIR/app-src/main.py" << 'EOF'
import socket
import time
import sys
import os

# Hardcoded dependencies - DO NOT CHANGE
DEPENDENCIES = [
    {"name": "Database", "host": "db.inventory.local", "port": 5432},
    {"name": "Cache", "host": "cache.inventory.local", "port": 6379},
    {"name": "Auth", "host": "auth.provider.external", "port": 80}
]

def check_connection(name, host, port):
    print(f"Checking connection to {name} ({host}:{port})...")
    retries = 5
    while retries > 0:
        try:
            # First try DNS resolution
            ip = socket.gethostbyname(host)
            print(f"  Resolved {host} to {ip}")
            
            # Then try TCP connection
            s = socket.create_connection((host, port), timeout=2)
            s.close()
            print(f"  SUCCESS: Connected to {name}")
            return True
        except socket.gaierror:
            print(f"  DNS ERROR: Could not resolve {host}")
        except ConnectionRefusedError:
            print(f"  TCP ERROR: Connection refused to {host}:{port}")
        except Exception as e:
            print(f"  ERROR: {e}")
        
        retries -= 1
        time.sleep(2)
    return False

def main():
    print("=== Legacy Inventory App v2.4 Starting ===")
    print("Initializing subsystems...")
    
    all_passed = True
    for dep in DEPENDENCIES:
        if not check_connection(dep["name"], dep["host"], dep["port"]):
            print(f"CRITICAL: Failed to connect to {dep['name']}. Aborting.")
            all_passed = False
    
    if all_passed:
        print("All systems go! Application started.")
        sys.stdout.flush()
        # Keep running
        while True:
            time.sleep(60)
    else:
        sys.exit(1)

if __name__ == "__main__":
    main()
EOF

# Create Dockerfile for App
cat > "$PROJECT_DIR/app-src/Dockerfile" << 'EOF'
FROM python:3.11-alpine
WORKDIR /app
COPY main.py .
CMD ["python", "-u", "main.py"]
EOF

# Create initial BROKEN docker-compose.yml
# It lacks the network aliases required for DNS resolution
cat > "$PROJECT_DIR/docker-compose.yml" << 'EOF'
services:
  app:
    build: ./app-src
    container_name: legacy-app
    depends_on:
      - postgres
      - redis
      - mock-auth
    restart: on-failure

  postgres:
    image: postgres:16-alpine
    container_name: postgres-db
    environment:
      POSTGRES_PASSWORD: password

  redis:
    image: redis:alpine
    container_name: redis-cache

  mock-auth:
    image: nginx:alpine
    container_name: auth-service
EOF

# Set permissions
chown -R ga:ga "$PROJECT_DIR"

# Wait for Docker daemon
wait_for_docker_daemon 60

# Stop any existing containers from previous runs
cd "$PROJECT_DIR"
docker compose down 2>/dev/null || true

# Start the broken stack so the user sees the error immediately
echo "Starting initial stack (expected to fail)..."
su - ga -c "cd $PROJECT_DIR && docker compose up -d --build" || true

# Wait a moment for containers to attempt start
sleep 5

# Focus Docker Desktop
focus_docker_desktop

# Take initial screenshot showing the failed state (likely)
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="