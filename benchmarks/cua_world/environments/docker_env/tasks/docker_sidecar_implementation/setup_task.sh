#!/bin/bash
# Setup script for docker_sidecar_implementation task
set -e
echo "=== Setting up Sidecar Pattern Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Wait for Docker
wait_for_docker

# 1. Prepare Project Directory
PROJECT_DIR="/home/ga/projects/settlement-system"
LEGACY_SRC="$PROJECT_DIR/legacy-src"
mkdir -p "$LEGACY_SRC"

# 2. Create the "Black Box" Legacy Application
# This simulates a vendor app that writes to disk instead of stdout
cat > "$LEGACY_SRC/settlement_core.py" << 'EOF'
import time
import os
import datetime
import sys
import signal

# Paths defined by "vendor"
AUDIT_DIR = "/var/opt/settlement/audit"
REPORT_DIR = "/var/opt/settlement/reports"
LOG_FILE = os.path.join(AUDIT_DIR, "transaction.log")

def handle_sigterm(*args):
    print("Received SIGTERM, shutting down...")
    sys.exit(0)

signal.signal(signal.SIGTERM, handle_sigterm)

print("Starting Settlement Core System v2.4...")
print(f"Audit logs will be written to: {LOG_FILE}")
print(f"Reports will be generated in: {REPORT_DIR}")

# Ensure directories exist
os.makedirs(AUDIT_DIR, exist_ok=True)
os.makedirs(REPORT_DIR, exist_ok=True)

txn_counter = 1000

while True:
    timestamp = datetime.datetime.now().isoformat()
    
    # Write Audit Log to DISK (not stdout)
    try:
        with open(LOG_FILE, "a") as f:
            log_entry = f"{timestamp} | TXN_ID_{txn_counter} | STATUS=SETTLED | AMOUNT=450.00\n"
            f.write(log_entry)
            f.flush()
    except Exception as e:
        print(f"Error writing log: {e}")

    # Generate/Update HTML Report
    try:
        with open(os.path.join(REPORT_DIR, "latest.html"), "w") as f:
            html_content = f"""
            <html>
            <head><title>Settlement Status</title></head>
            <body>
                <h1>Daily Settlement Report</h1>
                <p>Last Updated: {timestamp}</p>
                <p>Latest Transaction: TXN_ID_{txn_counter}</p>
                <p>System Status: NOMINAL</p>
            </body>
            </html>
            """
            f.write(html_content)
    except Exception as e:
        print(f"Error writing report: {e}")

    txn_counter += 1
    # Sleep 3 seconds
    time.sleep(3)
EOF

# 3. Create Dockerfile for Legacy App
cat > "$LEGACY_SRC/Dockerfile" << 'EOF'
FROM python:3.11-slim
WORKDIR /app
COPY settlement_core.py .
# Create directories to ensure permissions (simplified for task)
RUN mkdir -p /var/opt/settlement/audit && \
    mkdir -p /var/opt/settlement/reports && \
    chmod -R 777 /var/opt/settlement
CMD ["python", "-u", "settlement_core.py"]
EOF

# 4. Build the Legacy Image (Pre-built for the agent)
echo "Building legacy vendor image..."
docker build -t legacy-settlement:v2.4 "$LEGACY_SRC"

# 5. Create Initial docker-compose.yml
# This is what the agent starts with
cat > "$PROJECT_DIR/docker-compose.yml" << 'EOF'
version: '3.8'

services:
  legacy-core:
    image: legacy-settlement:v2.4
    container_name: legacy-core
    # The vendor says data is at /var/opt/settlement/
    # But currently, this data is lost when container restarts!
    # And we can't see the logs!
    
    # TODO: Add volumes and sidecars here
EOF

# 6. Cleanup and Permissions
rm -rf "$LEGACY_SRC" # Hide source code to simulate black box (agent inspects image/running container)
chown -R ga:ga "$PROJECT_DIR"

# 7. Record Start Time
date +%s > /tmp/task_start_timestamp

# 8. Setup Terminal
su - ga -c "DISPLAY=:1 gnome-terminal --maximize -- bash -c 'cd ~/projects/settlement-system && echo \"Settlement System Migration Task\"; echo \"Current Status: Legacy app logs to disk (hidden) and reports are inaccessible.\"; echo \"Goal: Use sidecars to stream logs and serve reports.\"; echo; ls -la; exec bash'" > /tmp/sidecar_terminal.log 2>&1 &

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="