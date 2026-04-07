#!/bin/bash
# Pre-task setup for audit_tiu_definitions
set -e

echo "=== Setting up Audit TIU Definitions Task ==="

# 1. Record Start Time (Anti-gaming)
date +%s > /tmp/task_start_timestamp

# 2. Prepare workspace
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents
# Remove any previous report to ensure clean state
rm -f /home/ga/Documents/tiu_titles_report.txt

# 3. Ensure VistA Container is Running
if ! docker ps --filter "name=vista-vehu" --filter "status=running" -q | grep -q .; then
    echo "Starting VistA container..."
    # The env start hook usually handles this, but we verify here
    exit 1 # Fail if not running, framework should handle start
fi

# 4. Ensure YDBGui is running (No Auth)
# We check if ydbgui is running in the container
if ! docker exec vista-vehu pgrep -f "ydbgui" > /dev/null; then
    echo "Starting YDBGui service..."
    docker exec -u vehu vista-vehu bash -c 'source /home/vehu/etc/env && nohup yottadb -run %ydbgui --port 8089 > /home/vehu/log/ydbgui-task.log 2>&1 &'
    sleep 5
fi

# 5. Launch Firefox to Dashboard
# Get Container IP
CONTAINER_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' vista-vehu)
URL="http://${CONTAINER_IP}:8089/"

echo "Launching Firefox..."
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '$URL' &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "firefox"; then
            break
        fi
        sleep 1
    done
    sleep 5
fi

# 6. Window Management
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true

# 7. Initial Screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="