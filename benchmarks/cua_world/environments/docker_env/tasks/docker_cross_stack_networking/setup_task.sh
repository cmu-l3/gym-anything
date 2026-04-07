#!/bin/bash
# Setup script for docker_cross_stack_networking task
# Creates two separate Docker Compose projects that fail to communicate via localhost.

set -e
echo "=== Setting up Docker Cross-Stack Networking Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Fallback for utils
if ! type wait_for_docker &>/dev/null; then
    wait_for_docker() {
        for i in {1..60}; do
            if docker info > /dev/null 2>&1; then return 0; fi
            sleep 2
        done; return 1
    }
fi
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

wait_for_docker

# Clean up any previous state
echo "Cleaning up previous containers..."
docker rm -f inventory-api storefront-web 2>/dev/null || true
docker network prune -f >/dev/null 2>&1 || true

# Base Projects Directory
PROJECTS_DIR="/home/ga/projects"
mkdir -p "$PROJECTS_DIR"

# ==============================================================================
# 1. Setup Inventory Service (Python Flask)
# ==============================================================================
INV_DIR="$PROJECTS_DIR/inventory-service"
mkdir -p "$INV_DIR"

# Create Flask App
cat > "$INV_DIR/app.py" << 'EOF'
from flask import Flask, jsonify
import os

app = Flask(__name__)

# Realistic product data
products = [
    {"id": 1, "name": "Quantum Widget", "price": 49.99, "stock": 100},
    {"id": 2, "name": "Hyper Gadget", "price": 129.50, "stock": 45},
    {"id": 3, "name": "Nano Bot", "price": 12.99, "stock": 200},
    {"id": 4, "name": "Mega Mechanism", "price": 899.00, "stock": 5},
    {"id": 5, "name": "Giga Gear", "price": 24.50, "stock": 150}
]

@app.route('/api/products')
def get_products():
    return jsonify(products)

@app.route('/health')
def health():
    return jsonify({"status": "healthy"})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

# Create Requirements
echo "flask==2.0.1" > "$INV_DIR/requirements.txt"

# Create Dockerfile
cat > "$INV_DIR/Dockerfile" << 'EOF'
FROM python:3.9-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
CMD ["python", "app.py"]
EOF

# Create docker-compose.yml (Standard, isolated network)
cat > "$INV_DIR/docker-compose.yml" << 'EOF'
version: '3.8'
services:
  api:
    build: .
    container_name: inventory-api
    ports:
      - "5001:5000"
    restart: always
EOF

# ==============================================================================
# 2. Setup Storefront App (Node.js Express)
# ==============================================================================
STORE_DIR="$PROJECTS_DIR/storefront-app"
mkdir -p "$STORE_DIR"

# Create Express App
cat > "$STORE_DIR/server.js" << 'EOF'
const express = require('express');
const http = require('http');
const app = express();

// The bug: defaulting to localhost will fail inside container
const API_URL = process.env.API_URL || 'http://localhost:5000';

app.get('/', (req, res) => {
    console.log(`Attempting to fetch products from ${API_URL}...`);
    
    const request = http.get(`${API_URL}/api/products`, (apiRes) => {
        let data = '';
        apiRes.on('data', (chunk) => data += chunk);
        apiRes.on('end', () => {
            try {
                const products = JSON.parse(data);
                let html = `
                    <html><head><title>Acme Store</title>
                    <style>body{font-family:sans-serif;padding:20px;}</style></head>
                    <body>
                    <h1>Acme Corp Store</h1>
                    <ul>`;
                products.forEach(p => {
                    html += `<li><b>${p.name}</b>: $${p.price}</li>`;
                });
                html += '</ul></body></html>';
                res.send(html);
            } catch (e) {
                res.send(`<h1>Error parsing data</h1><p>${e.message}</p>`);
            }
        });
    });

    request.on('error', (err) => {
        console.error(`API Request failed: ${err.message}`);
        res.send(`
            <html><head><title>Store Unavailable</title></head>
            <body>
            <h1>Store Unavailable</h1>
            <p style="color:red;">Could not connect to Inventory API.</p>
            <p><strong>Configured API URL:</strong> ${API_URL}</p>
            <p><strong>Error:</strong> ${err.message}</p>
            <hr>
            <h3>Troubleshooting Info:</h3>
            <p>The storefront container tried to reach the API but failed. 
            If you see 'ECONNREFUSED 127.0.0.1', it means I am trying to connect to myself!</p>
            </body></html>
        `);
    });
});

app.listen(3000, () => console.log('Storefront running on port 3000'));
EOF

# Create package.json
cat > "$STORE_DIR/package.json" << 'EOF'
{
  "name": "storefront",
  "version": "1.0.0",
  "main": "server.js",
  "scripts": {
    "start": "node server.js"
  },
  "dependencies": {
    "express": "^4.17.1"
  }
}
EOF

# Create Dockerfile
cat > "$STORE_DIR/Dockerfile" << 'EOF'
FROM node:18-bullseye-slim
WORKDIR /app
COPY package.json .
RUN npm install
COPY . .
CMD ["node", "server.js"]
EOF

# Create docker-compose.yml (The configuration bug is here)
cat > "$STORE_DIR/docker-compose.yml" << 'EOF'
version: '3.8'
services:
  web:
    build: .
    container_name: storefront-web
    ports:
      - "3000:3000"
    environment:
      # BUG: Pointing to localhost inside a container refers to the container itself
      - API_URL=http://localhost:5000
    restart: always
EOF

# Change ownership
chown -R ga:ga "$PROJECTS_DIR"

# ==============================================================================
# 3. Start the Broken Environment
# ==============================================================================
echo "Starting Inventory Service..."
cd "$INV_DIR"
su - ga -c "docker compose up -d --build"

echo "Starting Storefront App..."
cd "$STORE_DIR"
su - ga -c "docker compose up -d --build"

# Record Task Start Time
date +%s > /tmp/task_start_timestamp

# Create Desktop directory
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# Launch Terminal with context
su - ga -c "DISPLAY=:1 gnome-terminal --maximize -- bash -c 'cd ~/projects && echo \"=== Docker Networking Task ===\"; echo \"Services are running in: ~/projects/inventory-service and ~/projects/storefront-app\"; echo \"Problem: Storefront cannot reach Inventory API.\"; echo \"Test it: curl http://localhost:3000\"; echo; exec bash'" > /tmp/terminal_launch.log 2>&1 &
sleep 5

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Inventory API running on localhost:5001"
echo "Storefront Web running on localhost:3000 (Broken)"