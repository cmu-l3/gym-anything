#!/bin/bash
set -e
echo "=== Setting up Docker Compose Parameterization Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Wait for Docker to be ready
wait_for_docker

# Define project paths
PROJECT_DIR="/home/ga/projects/inventory-system"
APP_DIR="$PROJECT_DIR/app"

# Clean up any previous runs
echo "Cleaning up..."
if [ -d "$PROJECT_DIR" ]; then
    cd "$PROJECT_DIR"
    docker compose down --volumes --remove-orphans 2>/dev/null || true
    cd /
    rm -rf "$PROJECT_DIR"
fi

# Create directory structure
mkdir -p "$APP_DIR"

# 1. Create the dummy Node.js Application
echo "Creating application files..."
cat > "$APP_DIR/package.json" <<EOF
{
  "name": "inventory-system",
  "version": "1.0.0",
  "description": "Dummy Inventory System",
  "main": "server.js",
  "scripts": {
    "start": "node server.js"
  },
  "dependencies": {
    "express": "^4.18.2"
  }
}
EOF

cat > "$APP_DIR/server.js" <<'EOF'
const express = require('express');
const app = express();
const port = 3000; // Internal port, do not change

const mode = process.env.APP_MODE || 'unknown';
const dbHost = process.env.DB_HOST || 'localhost';

app.get('/', (req, res) => {
  res.send(`Inventory System Running.\nMode: ${mode}\nDB Host: ${dbHost}\n`);
});

app.listen(port, () => {
  console.log(`Inventory app listening on port ${port}`);
});
EOF

cat > "$APP_DIR/Dockerfile" <<EOF
ARG NODE_VERSION=18-slim
FROM node:\${NODE_VERSION}
WORKDIR /app
COPY package.json .
RUN npm install
COPY . .
CMD ["npm", "start"]
EOF

# 2. Create the HARDCODED docker-compose.yml
# This is the "Before" state the agent must fix
echo "Creating hardcoded docker-compose.yml..."
cat > "$PROJECT_DIR/docker-compose.yml" <<EOF
version: '3.8'

services:
  inventory-db:
    image: postgres:14
    environment:
      POSTGRES_USER: admin
      POSTGRES_PASSWORD: dev_password
      POSTGRES_DB: inventory
    volumes:
      - db_data:/var/lib/postgresql/data
    networks:
      - inventory-net

  inventory-web:
    build:
      context: ./app
      dockerfile: Dockerfile
    image: inventory-app:latest
    ports:
      - "3000:3000"
    environment:
      DB_HOST: inventory-db
      APP_MODE: development
    depends_on:
      - inventory-db
    networks:
      - inventory-net

networks:
  inventory-net:

volumes:
  db_data:
EOF

# Set permissions
chown -R ga:ga "$PROJECT_DIR"

# Pre-pull images to speed up the task for the agent
# We pull both the "dev" versions (current) and "prod" versions (target)
# so the agent doesn't waste time downloading.
echo "Pre-pulling images..."
docker pull postgres:14 >/dev/null 2>&1 || true
docker pull node:18-slim >/dev/null 2>&1 || true
docker pull postgres:15 >/dev/null 2>&1 || true
docker pull node:20-slim >/dev/null 2>&1 || true

# Record start time
date +%s > /tmp/task_start_time.txt

# Create a useful starting terminal
su - ga -c "DISPLAY=:1 gnome-terminal --maximize -- bash -c 'cd ~/projects/inventory-system && echo \"Inventory System Project Ready\"; echo \"Current Status: Hardcoded Configuration\"; ls -la; exec bash'" > /tmp/terminal_launch.log 2>&1 &

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="