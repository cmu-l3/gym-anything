#!/bin/bash
set -e
echo "=== Setting up resolve_microservice_port_conflict task ==="

# Record task start time
date +%s > /tmp/task_start_timestamp

# Ensure MariaDB and MongoDB are running
systemctl start mariadb 2>/dev/null || true
systemctl start mongod 2>/dev/null || true
sleep 2

# Stop user-service if it is currently running in PM2
echo "Stopping user-service if running..."
cd /opt/socioboard/socioboard-api/user && pm2 stop user-service 2>/dev/null || true
pm2 delete user-service 2>/dev/null || true

# Kill anything currently on port 3000 just to be safe
fuser -k 3000/tcp 2>/dev/null || true
sleep 1

# Create rogue analytics script
echo "Creating rogue process on port 3000..."
cat << 'EOF' > /tmp/rogue_analytics.py
import socket
import time
import sys

def start_server():
    host = '0.0.0.0'
    port = 3000
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.bind((host, port))
        s.listen(5)
        print(f"Legacy analytics script running on {host}:{port}")
        while True:
            time.sleep(10)
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)

if __name__ == '__main__':
    start_server()
EOF

# Start rogue script in background
nohup python3 /tmp/rogue_analytics.py > /tmp/rogue.log 2>&1 &
ROGUE_PID=$!
echo "$ROGUE_PID" > /tmp/rogue_pid.txt

sleep 2

# Verify rogue process is running on port 3000
if ! lsof -i :3000 > /dev/null 2>&1; then
    echo "WARNING: Rogue process failed to bind to port 3000"
fi

# Start user-service via PM2. It should fail to bind.
echo "Starting user-service in PM2 (should conflict)..."
cd /opt/socioboard/socioboard-api/user && pm2 start user.js --name "user-service" 2>/dev/null || true

# Start other microservices so environment looks normal
for svc in feeds publish notification; do
    cd /opt/socioboard/socioboard-api/$svc && pm2 start $svc.js --name "$svc-service" 2>/dev/null || true
done

sleep 3

# Record the MD5 checksum of the development.json configuration file
CONFIG_FILE="/opt/socioboard/socioboard-api/user/config/development.json"
if [ -f "$CONFIG_FILE" ]; then
    md5sum "$CONFIG_FILE" | awk '{print $1}' > /tmp/config_md5_initial.txt
else
    echo "MISSING" > /tmp/config_md5_initial.txt
fi

# Open a terminal on the desktop for the agent
su - ga -c "DISPLAY=:1 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus gnome-terminal --working-directory=/home/ga &" || \
su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga &"

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_start.png 2>/dev/null || true

echo "=== Setup complete ==="