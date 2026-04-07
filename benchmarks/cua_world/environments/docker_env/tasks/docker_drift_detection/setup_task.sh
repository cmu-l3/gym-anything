#!/bin/bash
set -e
echo "=== Setting up Docker Drift Detection Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Wait for Docker daemon
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

# Cleanup any previous state
echo "Cleaning up containers..."
docker rm -f acme-webserver acme-appserver acme-taskrunner 2>/dev/null || true
docker rm -f acme-webserver-clean acme-appserver-clean acme-taskrunner-clean 2>/dev/null || true
rm -rf /home/ga/projects/container-configs 2>/dev/null || true
rm -f /home/ga/Desktop/drift_report.txt 2>/dev/null || true

# Setup directories
mkdir -p /home/ga/projects/container-configs
chown -R ga:ga /home/ga/projects
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# ------------------------------------------------------------------
# 1. Setup acme-webserver (nginx:1.24-alpine)
# Drift: curl installed (bad), default.conf modified (good), maintenance.html added (good)
# ------------------------------------------------------------------
echo "Setting up acme-webserver..."
docker run -d --name acme-webserver nginx:1.24-alpine

# Apply drift
echo "Applying drift to webserver..."
# Install curl (unauthorized change)
docker exec acme-webserver apk update >/dev/null 2>&1
docker exec acme-webserver apk add curl >/dev/null 2>&1
# Modify config (legitimate change to preserve)
docker exec acme-webserver sh -c 'echo "server { listen 80; location / { root /usr/share/nginx/html; } location /status { return 200 \"OK\"; } }" > /etc/nginx/conf.d/default.conf'
# Add content (legitimate change to preserve)
docker exec acme-webserver sh -c 'echo "<h1>Maintenance</h1>" > /usr/share/nginx/html/maintenance.html'

# ------------------------------------------------------------------
# 2. Setup acme-appserver (python:3.11-slim)
# Drift: debugpy installed (bad), config.json modified (good), hotfix.py added (bad)
# ------------------------------------------------------------------
echo "Setting up acme-appserver..."
# Run a long-running command
docker run -d --name acme-appserver python:3.11-slim sh -c "mkdir /app && echo '{}' > /app/config.json && sleep infinity"

# Apply drift
echo "Applying drift to appserver..."
# Install debugpy (unauthorized)
docker exec acme-appserver pip install debugpy >/dev/null 2>&1
# Modify config (legitimate)
docker exec acme-appserver sh -c 'echo "{\"db_host\": \"db-replica\", \"retries\": 5}" > /app/config.json'
# Add hotfix code (unauthorized - should be in image build)
docker exec acme-appserver sh -c 'echo "print(\"Emergency fix\")" > /app/hotfix_001.py'

# ------------------------------------------------------------------
# 3. Setup acme-taskrunner (alpine:3.19)
# Drift: backup.sh added (good), crontab modified (good), custom_env.sh added (good)
# ------------------------------------------------------------------
echo "Setting up acme-taskrunner..."
docker run -d --name acme-taskrunner alpine:3.19 crond -f

# Apply drift
echo "Applying drift to taskrunner..."
# Add script (legitimate)
docker exec acme-taskrunner sh -c 'mkdir -p /scripts && echo "#!/bin/sh\necho backup" > /scripts/backup.sh && chmod +x /scripts/backup.sh'
# Modify crontab (legitimate)
docker exec acme-taskrunner sh -c 'echo "0 * * * * /scripts/backup.sh" >> /etc/crontabs/root'
# Add env (legitimate)
docker exec acme-taskrunner sh -c 'echo "export ENV=prod" > /etc/profile.d/custom_env.sh'

# ------------------------------------------------------------------
# Finalize Setup
# ------------------------------------------------------------------

# Record Task Start Time
date +%s > /tmp/task_start_time.txt

# Launch terminal for agent
su - ga -c "DISPLAY=:1 gnome-terminal --maximize -- bash -c 'echo \"=== Incident Response: Container Drift Detected ===\"; echo; echo \"The following containers have been flagged for unauthorized changes:\"; docker ps --format \"table {{.Names}}\t{{.Image}}\t{{.Status}}\"; echo; echo \"Your task:\"; echo \"1. Identify what changed (docker diff)\"; echo \"2. Extract authorized configs to ~/projects/container-configs/\"; echo \"3. Write report to ~/Desktop/drift_report.txt\"; echo \"4. Redeploy clean containers\"; exec bash'" > /tmp/terminal_launch.log 2>&1 &

sleep 2

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="