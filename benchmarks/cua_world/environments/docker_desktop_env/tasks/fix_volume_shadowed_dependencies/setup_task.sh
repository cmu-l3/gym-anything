#!/bin/bash
set -e
echo "=== Setting up fix_volume_shadowed_dependencies task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

PROJECT_DIR="/home/ga/projects/shadow-bug"
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR"

# 1. Create Application Code
cat > "$PROJECT_DIR/server.js" << 'EOF'
const express = require('express');
const app = express();
const port = 3000;

app.get('/', (req, res) => {
  res.send('Hello from Docker!');
});

app.listen(port, () => {
  console.log(`Shadow app listening on port ${port}`);
});
EOF

# 2. Create package.json
cat > "$PROJECT_DIR/package.json" << 'EOF'
{
  "name": "shadow-bug",
  "version": "1.0.0",
  "description": "Demo for volume shadowing",
  "main": "server.js",
  "scripts": {
    "start": "node server.js"
  },
  "dependencies": {
    "express": "^4.18.2"
  }
}
EOF

# 3. Create Dockerfile (Correctly installs modules)
cat > "$PROJECT_DIR/Dockerfile" << 'EOF'
FROM node:20-alpine
WORKDIR /app
COPY package.json .
RUN npm install
COPY . .
CMD ["npm", "start"]
EOF

# 4. Create Broken Docker Compose (The Trap)
# This mounts .:/app which shadows /app/node_modules from the image
cat > "$PROJECT_DIR/docker-compose.yml" << 'EOF'
services:
  app:
    build: .
    container_name: shadow-app
    ports:
      - "3000:3000"
    volumes:
      - .:/app
    environment:
      - NODE_ENV=development
EOF

# 5. Pre-build the image
# This ensures the image exists with node_modules populated,
# but the container will fail at runtime due to the mount.
echo "Pre-building image..."
cd "$PROJECT_DIR"
docker compose build

# Ensure no host node_modules exists (critical for the bug to manifest)
rm -rf "$PROJECT_DIR/node_modules"

# Set permissions
chown -R ga:ga "$PROJECT_DIR"

# Ensure Docker Desktop is running
if ! docker_desktop_running; then
    echo "Starting Docker Desktop..."
    su - ga -c "DISPLAY=:1 XDG_RUNTIME_DIR=/run/user/1000 /opt/docker-desktop/bin/docker-desktop > /tmp/docker-desktop.log 2>&1 &"
    sleep 10
fi

wait_for_docker_daemon 60

# Maximize Docker Desktop
focus_docker_desktop

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "Project located at: $PROJECT_DIR"
echo "To reproduce bug: cd $PROJECT_DIR && docker compose up"