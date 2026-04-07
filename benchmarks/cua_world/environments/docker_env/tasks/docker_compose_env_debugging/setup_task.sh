#!/bin/bash
# Setup script for docker_compose_env_debugging
set -e
echo "=== Setting up Docker Compose Env Debugging Task ==="

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

# Cleanup previous
docker rm -f finance-app 2>/dev/null || true
rm -rf /home/ga/projects/finance-core

# Create Project Directory
PROJECT_DIR="/home/ga/projects/finance-core"
mkdir -p "$PROJECT_DIR"

# 1. Create Mock Application (Python Script)
cat > "$PROJECT_DIR/app.py" << 'EOF'
import os
import sys
import time

def main():
    print("--- Finance Core v2.1.0 ---")
    print("Initializing connection pool...")
    
    # Read environment variables
    db_host = os.environ.get("DB_HOST", "undefined")
    db_pass = os.environ.get("DB_PASSWORD", "undefined")
    region = os.environ.get("API_REGION", "undefined")
    
    print(f"DEBUG: Configured Host: {db_host}")
    print(f"DEBUG: Region: {region}")
    
    # Simulation Logic
    if db_host == "dev-db":
        print("ERROR: ConnectionRefused. Host 'dev-db' is not reachable from this network.")
        print("HINT: Are you trying to connect to production with dev settings?")
        sys.exit(1)
        
    if db_host == "prod-db-01":
        # Check password correctness
        expected_pass = "Secure$tring!2024"
        if db_pass == expected_pass:
            print(f"SUCCESS: Authentication accepted for user 'admin'.")
            print("CONNECTION ESTABLISHED to prod-db-01")
            
            # Keep running to simulate a healthy service
            print("Service Ready. Listening on port 8080...")
            while True:
                time.sleep(10)
        else:
            # Mask password in logs for security, but show length to help debug
            masked_pass = "*" * len(db_pass)
            print(f"ERROR: Authentication failed for host 'prod-db-01'.")
            print(f"DEBUG: Received password length: {len(db_pass)}")
            if "$" not in db_pass and "tring" in db_pass:
                 print("DEBUG: Warning - It looks like the '$' character might have been lost/interpolated.")
            sys.exit(1)
            
    print(f"ERROR: Unknown host '{db_host}'. expected 'prod-db-01' or 'dev-db'")
    sys.exit(1)

if __name__ == "__main__":
    main()
EOF

# 2. Create Dockerfile
cat > "$PROJECT_DIR/Dockerfile" << 'EOF'
FROM python:3.9-slim
WORKDIR /app
COPY app.py .
CMD ["python", "-u", "app.py"]
EOF

# 3. Create BROKEN docker-compose.yml (Hardcoded values)
cat > "$PROJECT_DIR/docker-compose.yml" << 'EOF'
services:
  app:
    build: .
    container_name: finance-app
    environment:
      # Developer defaults - DO NOT DEPLOY TO PROD WITH THESE!
      - DB_HOST=dev-db
      - DB_PASSWORD=devpass
      - API_REGION=us-east-1
EOF

# 4. Create .env.prod (Correct values)
cat > "$PROJECT_DIR/.env.prod" << 'EOF'
# Production Configuration
DB_HOST=prod-db-01
DB_PASSWORD=Secure$tring!2024
API_REGION=eu-west-1
EOF

# 5. Create Startup Script
cat > "$PROJECT_DIR/start_prod.sh" << 'EOF'
#!/bin/bash
echo "Starting Finance Core in PRODUCTION mode..."
docker compose --env-file .env.prod up -d --build
echo "Container started. Checking logs..."
sleep 2
docker logs finance-app
EOF
chmod +x "$PROJECT_DIR/start_prod.sh"

# Fix Permissions
chown -R ga:ga "$PROJECT_DIR"

# Build the initial image so the agent doesn't waste time downloading python base
echo "Pre-building base image..."
cd "$PROJECT_DIR"
docker build -t finance-core-app:latest . >/dev/null 2>&1 || true

# Record Task Start Time
date +%s > /tmp/task_start_timestamp

# Open Terminal
su - ga -c "DISPLAY=:1 gnome-terminal --maximize -- bash -c 'cd ~/projects/finance-core && echo \"Docker Compose Debug Task\"; echo \"To start app: ./start_prod.sh\"; echo; ls -la; exec bash'" > /tmp/terminal.log 2>&1 &
sleep 3

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="