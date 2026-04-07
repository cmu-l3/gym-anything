#!/bin/bash
set -e
echo "=== Setting up Docker Compose Profiles Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Wait for Docker to be ready
wait_for_docker

# Define project directory
PROJECT_DIR="/home/ga/projects/acme-stack"
mkdir -p "$PROJECT_DIR"

# Create the initial "monolithic" docker-compose.yml
# We use images known to be in the environment (nginx, python-slim, redis, postgres) to ensure offline capability
cat > "$PROJECT_DIR/docker-compose.yml" << 'EOF'
version: '3.8'

services:
  # --- Core Services (Should start by default) ---
  api:
    image: python:3.11-slim
    command: python -m http.server 8000
    ports:
      - "8000:8000"
    networks:
      - app-net
    depends_on:
      - database
      - cache

  database:
    image: postgres:14
    environment:
      POSTGRES_PASSWORD: password
      POSTGRES_DB: acme
    networks:
      - app-net

  cache:
    image: redis:7-alpine
    networks:
      - app-net

  # --- Admin Tools (Should be profile: gui) ---
  db-admin:
    image: nginx:1.24-alpine
    environment:
      - TARGET=adminer
    ports:
      - "8080:80"
    networks:
      - app-net

  cache-admin:
    image: nginx:1.24-alpine
    environment:
      - TARGET=redis-commander
    ports:
      - "8081:80"
    networks:
      - app-net

  # --- Monitoring (Should be profile: monitoring) ---
  prometheus:
    image: nginx:1.24-alpine
    environment:
      - TARGET=prometheus
    ports:
      - "9090:9090"
    networks:
      - app-net

  grafana:
    image: nginx:1.24-alpine
    environment:
      - TARGET=grafana
    ports:
      - "3000:3000"
    networks:
      - app-net

  # --- Testing (Should be profile: test) ---
  test-runner:
    image: python:3.11-slim
    command: echo "Running tests..."
    networks:
      - app-net

  # --- Tools (Should be profile: tools) ---
  db-seeder:
    image: python:3.11-slim
    command: echo "Seeding database..."
    depends_on:
      - database
    networks:
      - app-net

networks:
  app-net:
    driver: bridge
EOF

# Set permissions
chown -R ga:ga "$PROJECT_DIR"

# Clean up any previous containers
cd "$PROJECT_DIR"
docker compose down --remove-orphans 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt

# Open a terminal for the agent
su - ga -c "DISPLAY=:1 gnome-terminal --maximize -- bash -c 'cd ~/projects/acme-stack && echo \"Docker Compose Profiles Task\"; echo \"Current behavior: docker compose up starts EVERYTHING (slow!)\"; echo \"Goal: Use profiles to categorize services.\"; echo; ls -l; exec bash'" > /tmp/terminal_launch.log 2>&1 &

sleep 3

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Project located at: $PROJECT_DIR"