#!/bin/bash
set -e
echo "=== Setting up recover_orphaned_volume_data task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create directory for hidden verification data
mkdir -p /home/ga/.hidden_task_data
chmod 700 /home/ga/.hidden_task_data

# Ensure Docker is ready
wait_for_docker_daemon 60

# 1. Clean up previous run artifacts
echo "Cleaning up previous state..."
docker rm -f recovery-env 2>/dev/null || true
docker volume prune -f 2>/dev/null || true

# 2. Generate Secret Token
# This token validates that the agent found the *specific* volume created for this session
SECRET_TOKEN="CONFIDENTIAL-BLUEPRINT-$(date +%s)-${RANDOM}-${RANDOM}"
echo "$SECRET_TOKEN" > /home/ga/.hidden_task_data/secret_token.txt

# 3. Create Decoy Volumes
echo "Creating decoy volumes..."

# Decoy 1: Empty Postgres-like volume
docker run --rm -v /var/lib/postgresql/data postgres:15-alpine sh -c 'echo "This is a decoy DB volume" > /dev/null' 2>/dev/null || \
docker run --rm -v /data alpine sh -c 'mkdir -p /data/base && touch /data/PG_VERSION'

# Decoy 2: Node modules cache (common debris)
docker run --rm -v /app/node_modules alpine sh -c "mkdir -p /app/node_modules/lodash && touch /app/node_modules/package.lock && echo '{}' > /app/node_modules/package.json"

# Decoy 3: Empty volume
docker volume create > /dev/null

# 4. Create Target Volume (The "Orphan")
echo "Creating target volume..."
# We start a container, populate the volume, then kill the container to leave the volume dangling
# We use a randomized project structure to make it look realistic
TARGET_VOL_ID=$(docker run -d -v /project-data alpine sh -c "
    mkdir -p /project-data/src
    echo 'def main(): pass' > /project-data/src/main.py
    echo '# Project X Blueprint' > /project-data/PROJECT_X_BLUEPRINT.md
    echo '' >> /project-data/PROJECT_X_BLUEPRINT.md
    echo 'SECRET_TOKEN=$SECRET_TOKEN' >> /project-data/PROJECT_X_BLUEPRINT.md
    echo 'CONFIDENTIAL DATA - DO NOT DISTRIBUTE' >> /project-data/PROJECT_X_BLUEPRINT.md
    touch /project-data/README.md
    sleep 10
")

# Wait a moment for writes to sync
sleep 3

# Remove container (force) to orphan the volume
docker rm -f "$TARGET_VOL_ID"

# 5. UI Setup
# Ensure Docker Desktop is running and focused
if ! docker_desktop_running; then
    echo "Starting Docker Desktop..."
    su - ga -c "DISPLAY=:1 XDG_RUNTIME_DIR=/run/user/1000 /opt/docker-desktop/bin/docker-desktop > /tmp/docker-desktop.log 2>&1 &"
    sleep 10
fi

focus_docker_desktop
# Maximize window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "docker" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Dismiss any dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "Setup complete. Target volume created and orphaned."
echo "Secret token stored in hidden location."