#!/bin/bash
# Setup script for container_timezone_locale_fix task

echo "=== Setting up container_timezone_locale_fix task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Wait for Docker daemon
wait_for_docker_daemon 60

# Define project directory
PROJECT_DIR="/home/ga/scheduler-bot"
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR"

# 1. Create the Python application (bot.py)
# This script prints time and tries to print Unicode.
# It simulates a crash if encoding is insufficient.
cat > "$PROJECT_DIR/bot.py" << 'PYEOF'
import datetime
import sys
import time
import os

print("--- BOT STARTING ---")

# Loop to keep container running for inspection, but do the work immediately
while True:
    try:
        # 1. Check Timezone
        # We print simple string to avoid format dependency, but include tzinfo
        now = datetime.datetime.now()
        tz_name = time.tzname
        print(f"CURRENT_TIME: {now} | TZ: {tz_name}")

        # 2. Check Unicode/Locale
        user_name = "Raphaël"
        print(f"PROCESSING_USER: {user_name}")
        print("STATUS: SUCCESS")
        
        # Sleep before repeating to simulate a daemon
        sys.stdout.flush()
        time.sleep(10)
        
    except UnicodeEncodeError as e:
        print(f"CRITICAL ERROR: UnicodeEncodeError - {e}")
        print("HINT: Set LANG/LC_ALL to a UTF-8 compatible locale.")
        sys.stdout.flush()
        # In a real app this might crash, here we sleep to allow user to see logs
        # but exit with error code eventually if we wanted strictness. 
        # For this task, we want the container to stay up so the agent can debug,
        # but the logs will show error.
        time.sleep(10)
    except Exception as e:
        print(f"ERROR: {e}")
        sys.stdout.flush()
        time.sleep(10)
PYEOF

# 2. Create the Broken Dockerfile
# - Uses Alpine (no tzdata by default)
# - No ENV vars for TZ or LANG
cat > "$PROJECT_DIR/Dockerfile" << 'DOCKERFILE'
FROM python:3.9-alpine

WORKDIR /app

COPY bot.py .

# Missing: apk add tzdata
# Missing: ENV TZ, ENV LANG

CMD ["python", "-u", "bot.py"]
DOCKERFILE

# 3. Create docker-compose.yml
cat > "$PROJECT_DIR/docker-compose.yml" << 'COMPOSE'
services:
  bot:
    build: .
    container_name: scheduler-bot
    # Missing: environment variables for TZ/LANG
COMPOSE

# Set permissions
chown -R ga:ga "$PROJECT_DIR"

# 4. Start the broken stack
# This allows the agent to see the "wrong" state immediately (UTC time, potential encoding issues)
echo "Starting initial broken container..."
cd "$PROJECT_DIR"
su - ga -c "docker compose up -d --build"

# Record start time
date +%s > /tmp/task_start_time.txt

# Open Terminal at the project directory
su - ga -c "gnome-terminal --working-directory='$PROJECT_DIR'" &
sleep 2

# Open Docker Desktop (optional but helpful context)
if ! docker_desktop_running; then
    su - ga -c "DISPLAY=:1 XDG_RUNTIME_DIR=/run/user/1000 /opt/docker-desktop/bin/docker-desktop > /dev/null 2>&1 &"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Project located at: $PROJECT_DIR"
echo "Container 'scheduler-bot' should be running but with incorrect config."