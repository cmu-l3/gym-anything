#!/bin/bash
set -e
echo "=== Setting up Docker Cron Legacy Migration Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Wait for Docker
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

# Create Project Directory
PROJECT_DIR="/home/ga/projects/legacy-etl"
mkdir -p "$PROJECT_DIR"

# 1. Create ingest.py
cat > "$PROJECT_DIR/ingest.py" << 'EOF'
import os
import datetime
import sys

def run_ingest():
    # These variables are passed to 'docker run -e ...'
    # The challenge is making sure cron sees them.
    endpoint = os.environ.get("API_ENDPOINT", "UNSET")
    token = os.environ.get("API_TOKEN", "UNSET")
    
    timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    
    print(f"[{timestamp}] Starting ingestion...")
    print(f"[{timestamp}] Connecting to {endpoint} with token {token}")
    
    if token == "UNSET" or endpoint == "UNSET":
        print(f"[{timestamp}] ERROR: Environment variables missing!")
        sys.exit(1)
    
    print(f"[{timestamp}] Ingestion complete.")

if __name__ == "__main__":
    run_ingest()
EOF

# 2. Create crontab.txt (Standard cron format, missing redirection/env handling)
cat > "$PROJECT_DIR/crontab.txt" << 'EOF'
# Run ingest script every minute
* * * * * python /app/ingest.py
EOF

# 3. Create Dockerfile skeleton
cat > "$PROJECT_DIR/Dockerfile" << 'EOF'
FROM python:3.9-slim

WORKDIR /app

# TODO: Install cron
# TODO: Copy files
# TODO: Setup crontab
# TODO: Handle environment variables
# TODO: Ensure output goes to stdout/stderr

CMD ["echo", "Please update Dockerfile to run cron"]
EOF

# 4. Create empty entrypoint.sh (hinting it might be useful)
touch "$PROJECT_DIR/entrypoint.sh"
chmod +x "$PROJECT_DIR/entrypoint.sh"

chown -R ga:ga "$PROJECT_DIR"

# Clean up any previous attempts
docker rm -f etl-test 2>/dev/null || true
docker rmi -f legacy-etl:latest 2>/dev/null || true

# Record start time
date +%s > /tmp/task_start_timestamp

# Open terminal
su - ga -c "DISPLAY=:1 gnome-terminal --maximize -- bash -c 'cd ~/projects/legacy-etl && echo \"Legacy ETL Cron Migration Task\"; echo \"-------------------------------\"; echo \"Files:\"; ls -1; echo; echo \"Goal: Containerize ingest.py so it runs via cron every minute.\"; echo \"      Env vars API_TOKEN/API_ENDPOINT must work.\"; echo \"      Logs must appear in docker logs.\"; echo; exec bash'" > /tmp/cron_terminal.log 2>&1 &

# Initial screenshot
if type take_screenshot &>/dev/null; then
    take_screenshot /tmp/task_start.png
fi

echo "=== Setup Complete ==="