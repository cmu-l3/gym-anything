#!/bin/bash
# Setup script for docker_cron_observability task

set -e
echo "=== Setting up Docker Cron Observability Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Helper to wait for Docker
if ! type wait_for_docker &>/dev/null; then
    wait_for_docker() {
        for i in {1..60}; do
            if docker info > /dev/null 2>&1; then return 0; fi
            sleep 2
        done; return 1
    }
fi

wait_for_docker

# Clean up any previous run
docker rm -f db-backup 2>/dev/null || true
rm -rf /home/ga/projects/db-backup

# Create project directory
PROJECT_DIR="/home/ga/projects/db-backup"
mkdir -p "$PROJECT_DIR"
chown ga:ga "$PROJECT_DIR"

# 1. Create the backup script (The "Business Logic")
# It fails if API_KEY is missing.
cat > "$PROJECT_DIR/backup.sh" << 'EOF'
#!/bin/bash
echo "[$(date)] Starting backup job..."

if [ -z "$API_KEY" ]; then
    echo "[$(date)] ERROR: API_KEY is missing! Cannot authenticate with storage."
    echo "[$(date)] Debug: Env vars available:"
    env
    exit 1
fi

if [ "$API_KEY" != "production_secret_123" ]; then
    echo "[$(date)] ERROR: Invalid API_KEY provided."
    exit 1
fi

echo "[$(date)] Authenticating with secure storage..."
# Simulate network latency
sleep 1
echo "[$(date)] Uploading database dump..."
sleep 1
echo "[$(date)] Backup payload delivered successfully."

# Create a success marker file (internal verification artifact)
echo "$(date)" > /tmp/last_backup_success
EOF
chmod +x "$PROJECT_DIR/backup.sh"
chown ga:ga "$PROJECT_DIR/backup.sh"

# 2. Create the Dockerfile
# Intentionally flawed:
# - Cron doesn't see ENV vars from Docker
# - Cron logs go to email or /var/log/cron.log inside, not stdout (PID 1)
cat > "$PROJECT_DIR/Dockerfile" << 'EOF'
FROM ubuntu:20.04

# Install cron and minimal tools
RUN apt-get update && apt-get install -y \
    cron \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy the backup script
COPY backup.sh /usr/local/bin/backup.sh
RUN chmod +x /usr/local/bin/backup.sh

# Setup the cron job (Flawed: no output redirection, no env loading)
# Runs every minute
RUN echo "* * * * * root /usr/local/bin/backup.sh" > /etc/cron.d/backup-cron

# Give execution rights on the cron job
RUN chmod 0644 /etc/cron.d/backup-cron

# Apply cron job
RUN crontab /etc/cron.d/backup-cron

# Create the log file to be able to run tail
RUN touch /var/log/cron.log

# Run the command on container startup
CMD ["cron", "-f"]
EOF
chown ga:ga "$PROJECT_DIR/Dockerfile"

# 3. Create docker-compose.yml
cat > "$PROJECT_DIR/docker-compose.yml" << 'EOF'
services:
  db-backup:
    build: .
    container_name: db-backup
    environment:
      - API_KEY=production_secret_123
    restart: always
EOF
chown ga:ga "$PROJECT_DIR/docker-compose.yml"

# Build and start the container
echo "Building and starting initial state..."
cd "$PROJECT_DIR"
# Run as ga user so permissions match agent context
su - ga -c "docker compose up -d --build"

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Wait a moment to ensure it's running and failing silently
sleep 5

# Verify initial state (for debugging setup)
echo "Verifying initial state (should show empty logs):"
docker logs db-backup || true

# Setup terminal for agent
su - ga -c "DISPLAY=:1 gnome-terminal --maximize -- bash -c 'cd ~/projects/db-backup && echo \"Task: Fix silent cron failures\"; echo \"Container db-backup is running.\"; echo \"Check logs with: docker logs db-backup\"; exec bash'" > /tmp/terminal.log 2>&1 &
sleep 2

take_screenshot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== Setup Complete ==="