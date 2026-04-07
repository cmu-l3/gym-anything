#!/bin/bash
# Setup script for docker_tls_mtls_setup task

set -e
echo "=== Setting up Docker mTLS Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Wait for Docker to be ready
if ! docker info > /dev/null 2>&1; then
    echo "Waiting for Docker daemon..."
    for i in {1..60}; do
        if docker info > /dev/null 2>&1; then break; fi
        sleep 2
    done
fi

# Clean up any previous run artifacts
echo "Cleaning up previous state..."
docker rm -f acme-gateway acme-tls-client 2>/dev/null || true
docker network rm acme-tls-net 2>/dev/null || true
rm -rf /home/ga/projects/tls-setup
rm -f /home/ga/Desktop/tls_verification.txt
rm -f /home/ga/Desktop/pki_documentation.txt

# Create Desktop if it doesn't exist
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# Record task start timestamp (anti-gaming)
date +%s > /tmp/task_start_time.txt

# Start a terminal for the user
su - ga -c "DISPLAY=:1 gnome-terminal --maximize -- bash -c 'echo \"mTLS Setup Task\"; echo \"Goal: Create CA, Server/Client Certs, and Nginx mTLS container\"; echo \"Working Directory: ~/projects/tls-setup/\"; echo; exec bash'" > /tmp/terminal_launch.log 2>&1 &
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="