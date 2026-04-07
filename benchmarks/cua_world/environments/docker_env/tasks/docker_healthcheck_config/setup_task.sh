#!/bin/bash
set -e

echo "=== Setting up Docker Healthcheck Configuration Task ==="

# Function to wait for Docker daemon
wait_for_docker() {
    for i in {1..60}; do
        if docker info > /dev/null 2>&1; then return 0; fi
        sleep 2
    done
    return 1
}

# Function to take screenshot
take_screenshot() {
    DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
}

wait_for_docker

# Clean up any previous run
rm -f /home/ga/Desktop/health_status.txt
if [ -d "/home/ga/projects/healthcheck-lab" ]; then
    cd "/home/ga/projects/healthcheck-lab"
    docker compose down -v 2>/dev/null || true
fi
docker rm -f healthlab-catalog healthlab-orders healthlab-db healthlab-cache 2>/dev/null || true

# Create project directory
PROJECT_DIR="/home/ga/projects/healthcheck-lab"
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR/product-catalog"
mkdir -p "$PROJECT_DIR/order-service"
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# === product-catalog (Node.js Express) ===
cat > "$PROJECT_DIR/product-catalog/package.json" << 'PKGJSON'
{
  "name": "product-catalog",
  "version": "1.0.0",
  "main": "server.js",
  "dependencies": {
    "express": "^4.18.2"
  }
}
PKGJSON

cat > "$PROJECT_DIR/product-catalog/server.js" << 'SERVERJS'
const express = require('express');
const app = express();

const products = [
  { id: 1, name: "Wireless Keyboard", price: 49.99 },
  { id: 2, name: "USB-C Hub", price: 34.99 }
];

app.get('/healthz', (req, res) => {
  res.status(200).json({ status: 'ok', service: 'product-catalog', timestamp: new Date().toISOString() });
});

app.get('/products', (req, res) => {
  res.json(products);
});

const PORT = 3000;
app.listen(PORT, '0.0.0.0', () => {
  console.log(`Product Catalog Service running on port ${PORT}`);
});
SERVERJS

cat > "$PROJECT_DIR/product-catalog/Dockerfile" << 'DOCKERFILE'
FROM node:20-slim
RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY package.json ./
RUN npm install --production
COPY server.js ./
EXPOSE 3000
CMD ["node", "server.js"]
DOCKERFILE

# === order-service (Python Flask) ===
cat > "$PROJECT_DIR/order-service/requirements.txt" << 'REQS'
flask==3.0.0
REQS

cat > "$PROJECT_DIR/order-service/app.py" << 'APPPY'
from flask import Flask, jsonify
from datetime import datetime

app = Flask(__name__)

@app.route('/health')
def health():
    return jsonify({"status": "ok", "service": "order-service", "timestamp": datetime.now().isoformat()})

@app.route('/orders')
def get_orders():
    return jsonify([])

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
APPPY

cat > "$PROJECT_DIR/order-service/Dockerfile" << 'DOCKERFILE'
FROM python:3.11-slim
RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py ./
EXPOSE 5000
CMD ["python", "app.py"]
DOCKERFILE

# === docker-compose.yml (NO health checks, NO restart policies) ===
cat > "$PROJECT_DIR/docker-compose.yml" << 'COMPOSEYML'
version: '3.8'

services:
  product-catalog:
    build: ./product-catalog
    container_name: healthlab-catalog
    ports:
      - "3000:3000"
    depends_on:
      - db
      - cache

  order-service:
    build: ./order-service
    container_name: healthlab-orders
    ports:
      - "5000:5000"
    depends_on:
      - db
      - cache

  db:
    image: postgres:14
    container_name: healthlab-db
    environment:
      POSTGRES_DB: appdb
      POSTGRES_USER: appuser
      POSTGRES_PASSWORD: apppass123
    volumes:
      - pgdata:/var/lib/postgresql/data

  cache:
    image: redis:7-alpine
    container_name: healthlab-cache

volumes:
  pgdata:
COMPOSEYML

# Set ownership
chown -R ga:ga "$PROJECT_DIR"

# Record task start time
date +%s > /tmp/task_start_time.txt

# Build and start the stack (simulating the state the agent finds)
echo "Building and starting initial services..."
cd "$PROJECT_DIR"
export DOCKER_BUILDKIT=1
docker compose build --quiet
docker compose up -d

# Wait for services to be running (but they won't have healthy status yet)
echo "Waiting for services to start..."
for i in {1..30}; do
    RUNNING=$(docker ps --filter "name=healthlab" --format '{{.Names}}' 2>/dev/null | wc -l)
    if [ "$RUNNING" -ge 4 ]; then
        echo "All 4 services running."
        break
    fi
    sleep 2
done

# Open terminal in project directory
su - ga -c "DISPLAY=:1 gnome-terminal --maximize --working-directory='$PROJECT_DIR' -- bash -c '
echo \"============================================\"
echo \"  Docker Healthcheck Configuration Lab\"
echo \"============================================\"
echo \"\"
echo \"Project directory: ~/projects/healthcheck-lab/\"
echo \"\"
echo \"Current services (NO health checks configured):\"
docker ps --format \"table {{.Names}}\t{{.Status}}\t{{.Ports}}\"
echo \"\"
echo \"Task:\"
echo \" 1. Add healthchecks to docker-compose.yml for all services\"
echo \" 2. Add restart policies (e.g., unless-stopped)\"
echo \" 3. Redeploy and verify they become (healthy)\"
echo \" 4. Save output of 'docker ps' to ~/Desktop/health_status.txt\"
echo \"\"
exec bash
'" > /tmp/terminal.log 2>&1 &

sleep 3
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="