#!/bin/bash
# Setup script for compose_profiles_multi_team task

echo "=== Setting up compose_profiles_multi_team task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create project directory
PROJECT_DIR="/home/ga/ecommerce-platform"
mkdir -p "$PROJECT_DIR"

# Wait for Docker Desktop to be ready
echo "Waiting for Docker Desktop..."
wait_for_docker_daemon 60

# Pre-pull images to ensure smooth agent experience
echo "Pre-pulling images..."
docker pull postgres:16-alpine &
docker pull redis:7-alpine &
docker pull nginx:alpine &
docker pull python:3.12-alpine &
docker pull node:20-alpine &
docker pull prom/prometheus:v2.51.0 &
wait

# Create the initial docker-compose.yml (NO profiles)
cat > "$PROJECT_DIR/docker-compose.yml" << 'EOF'
services:
  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: user
      POSTGRES_PASSWORD: password
      POSTGRES_DB: ecommerce
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U user -d ecommerce"]
      interval: 5s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 5s
      retries: 5

  nginx:
    image: nginx:alpine
    ports:
      - "8080:80"
    depends_on:
      - storefront
      - api

  storefront:
    image: node:20-alpine
    command: ["node", "-e", "console.log('Starting frontend...'); setInterval(() => {}, 1000);"]
    environment:
      - NODE_ENV=development
      - API_URL=http://api:5000
    ports:
      - "3000:3000"
    depends_on:
      - api

  api:
    image: python:3.12-alpine
    command: ["python3", "-c", "import time; print('Starting API...'); time.sleep(3600)"]
    environment:
      - DATABASE_URL=postgresql://user:password@postgres:5432/ecommerce
      - REDIS_URL=redis://redis:6379/0
    ports:
      - "5000:5000"
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy

  worker:
    image: python:3.12-alpine
    command: ["python3", "-c", "import time; print('Starting Worker...'); time.sleep(3600)"]
    environment:
      - DATABASE_URL=postgresql://user:password@postgres:5432/ecommerce
      - REDIS_URL=redis://redis:6379/0
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy

  test-runner:
    image: python:3.12-alpine
    command: ["python3", "-c", "print('Tests passed!');"]
    environment:
      - TEST_ENV=true
    depends_on:
      - api
      - worker

  prometheus:
    image: prom/prometheus:v2.51.0
    ports:
      - "9090:9090"

volumes:
  postgres_data:
EOF

# Set permissions
chown -R ga:ga "$PROJECT_DIR"

# Save copy of original for diffing
cp "$PROJECT_DIR/docker-compose.yml" /tmp/original_compose.yml

# Ensure clean state (no running containers)
docker compose -f "$PROJECT_DIR/docker-compose.yml" down -v --remove-orphans 2>/dev/null || true

# Focus VS Code or Terminal to hint at workflow? 
# We'll just focus Docker Desktop as per environment standard, 
# but also open the folder in file manager for convenience.
su - ga -c "DISPLAY=:1 nautilus $PROJECT_DIR &"
sleep 2

# Maximize Docker Desktop
focus_docker_desktop

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="