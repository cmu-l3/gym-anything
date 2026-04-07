#!/bin/bash
# Setup script for docker_compose_merge task

set -e
echo "=== Setting up Docker Compose Merge Task ==="

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

if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

wait_for_docker

# Cleanup previous runs
echo "Cleaning up..."
docker rm -f $(docker ps -a -q) 2>/dev/null || true
docker network prune -f 2>/dev/null || true
docker volume prune -f 2>/dev/null || true
rm -rf /home/ga/projects/team-alpha /home/ga/projects/team-beta /home/ga/projects/merged

# Create directories
mkdir -p /home/ga/projects/team-alpha/app
mkdir -p /home/ga/projects/team-beta/app
mkdir -p /home/ga/projects/merged

# ==============================================================================
# TEAM ALPHA SETUP (Auth Service)
# ==============================================================================
echo "Creating Team Alpha (Auth) project..."

# Python Flask Auth App
cat > /home/ga/projects/team-alpha/app/app.py << 'EOF'
from flask import Flask, jsonify
import os
import psycopg2
import redis

app = Flask(__name__)

@app.route('/health')
def health():
    return jsonify({"status": "ok", "service": "auth-api"})

@app.route('/auth/status')
def auth_status():
    # Check DB connection
    db_status = "unknown"
    try:
        conn = psycopg2.connect(
            host=os.environ.get("DATABASE_HOST", "db"),
            database=os.environ.get("POSTGRES_DB", "authdb"),
            user=os.environ.get("POSTGRES_USER", "postgres"),
            password=os.environ.get("POSTGRES_PASSWORD", "secret")
        )
        db_status = "connected"
        conn.close()
    except Exception as e:
        db_status = f"failed: {str(e)}"

    # Check Redis connection
    redis_status = "unknown"
    try:
        r = redis.from_url(os.environ.get("REDIS_URL", "redis://cache:6379"))
        r.ping()
        redis_status = "connected"
    except Exception as e:
        redis_status = f"failed: {str(e)}"
    
    return jsonify({
        "service": "auth-api",
        "database": db_status,
        "cache": redis_status
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

cat > /home/ga/projects/team-alpha/app/requirements.txt << 'EOF'
flask==3.0.0
psycopg2-binary==2.9.9
redis==5.0.1
EOF

cat > /home/ga/projects/team-alpha/app/Dockerfile << 'EOF'
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
CMD ["python", "app.py"]
EOF

# Alpha Docker Compose
cat > /home/ga/projects/team-alpha/docker-compose.yml << 'EOF'
version: '3.8'

services:
  auth-api:
    build: ./app
    image: acme-auth-api:latest
    ports:
      - "8080:5000"  # CONFLICT
    environment:
      - DATABASE_HOST=db
      - POSTGRES_DB=authdb
      - REDIS_URL=redis://cache:6379
    depends_on:
      - db
      - cache
    networks:
      - backend

  db:
    image: postgres:14
    ports:
      - "5432:5432"  # CONFLICT
    environment:
      - POSTGRES_DB=authdb
      - POSTGRES_PASSWORD=secret
    volumes:
      - db-data:/var/lib/postgresql/data  # CONFLICT
    networks:
      - backend

  cache:
    image: redis:7-alpine
    networks:
      - backend

networks:
  backend:  # CONFLICT

volumes:
  db-data:  # CONFLICT
EOF

# ==============================================================================
# TEAM BETA SETUP (Catalog Service)
# ==============================================================================
echo "Creating Team Beta (Catalog) project..."

# Node.js Express Catalog App
cat > /home/ga/projects/team-beta/app/package.json << 'EOF'
{
  "name": "catalog-api",
  "version": "1.0.0",
  "main": "server.js",
  "dependencies": {
    "express": "^4.18.2",
    "pg": "^8.11.3",
    "axios": "^1.6.0"
  }
}
EOF

cat > /home/ga/projects/team-beta/app/server.js << 'EOF'
const express = require('express');
const { Pool } = require('pg');
const axios = require('axios');
const app = express();
const port = 3000;

const pool = new Pool({
  host: process.env.DATABASE_HOST || 'db',
  database: process.env.POSTGRES_DB || 'catalogdb',
  user: process.env.POSTGRES_USER || 'postgres',
  password: process.env.POSTGRES_PASSWORD || 'secret',
});

app.get('/health', (req, res) => {
  res.json({ status: 'ok', service: 'catalog-api' });
});

app.get('/catalog/products', async (req, res) => {
  let dbStatus = 'unknown';
  try {
    const client = await pool.connect();
    client.release();
    dbStatus = 'connected';
  } catch (e) {
    dbStatus = 'failed: ' + e.message;
  }

  let searchStatus = 'unknown';
  try {
    await axios.get(process.env.SEARCH_URL || 'http://search:9200');
    searchStatus = 'connected';
  } catch (e) {
    // We expect a 404 or similar from the mock search, just checking connectivity
    if (e.response) searchStatus = 'connected';
    else searchStatus = 'failed: ' + e.message;
  }

  res.json({
    service: 'catalog-api',
    database: dbStatus,
    search: searchStatus
  });
});

app.listen(port, () => {
  console.log(`Catalog API listening on port ${port}`);
});
EOF

cat > /home/ga/projects/team-beta/app/Dockerfile << 'EOF'
FROM node:20-slim
WORKDIR /app
COPY package.json .
RUN npm install
COPY server.js .
CMD ["node", "server.js"]
EOF

# Beta Docker Compose
cat > /home/ga/projects/team-beta/docker-compose.yml << 'EOF'
version: '3.8'

services:
  catalog-api:
    build: ./app
    image: acme-catalog-api:latest
    ports:
      - "8080:3000"  # CONFLICT (same host port)
    environment:
      - DATABASE_HOST=db
      - POSTGRES_DB=catalogdb
      - SEARCH_URL=http://search:9200
    depends_on:
      - db
      - search
    networks:
      - backend

  db:
    image: postgres:14
    ports:
      - "5432:5432"  # CONFLICT
    environment:
      - POSTGRES_DB=catalogdb
      - POSTGRES_PASSWORD=secret
    volumes:
      - db-data:/var/lib/postgresql/data  # CONFLICT
    networks:
      - backend

  search:
    image: alpine:3.18
    command: ["sh", "-c", "apk add --no-cache socat && socat TCP-LISTEN:9200,fork,reuseaddr SYSTEM:'echo -e \"HTTP/1.1 200 OK\\n\\nSearch Service Ready\"'"]
    networks:
      - backend

networks:
  backend:  # CONFLICT

volumes:
  db-data:  # CONFLICT
EOF

# ==============================================================================
# INSTRUCTIONS
# ==============================================================================
cat > /home/ga/projects/MERGE_INSTRUCTIONS.txt << 'EOF'
TASK: Merge Team Alpha and Team Beta Projects

1. Analyze ~/projects/team-alpha/docker-compose.yml (Auth Service)
2. Analyze ~/projects/team-beta/docker-compose.yml (Catalog Service)
3. Create a unified stack in ~/projects/merged/docker-compose.yml
4. Resolve all conflicts:
   - Duplicate service names (e.g. 'db')
   - Duplicate container names or ports (8080, 5432)
   - Conflicting network and volume names
5. Update environment variables so APIs talk to the correct databases
6. Start the unified stack using 'docker compose up'

Goal: All 6 services running simultaneously with unique host ports.
EOF

# Build images in advance to save time for the agent
echo "Pre-building images..."
docker compose -f /home/ga/projects/team-alpha/docker-compose.yml build
docker compose -f /home/ga/projects/team-beta/docker-compose.yml build

# Set permissions
chown -R ga:ga /home/ga/projects

# Timestamp
date +%s > /tmp/task_start_time.txt

# Open Terminal
su - ga -c "DISPLAY=:1 gnome-terminal --maximize -- bash -c 'cd ~/projects; cat MERGE_INSTRUCTIONS.txt; echo; echo \"Projects are in team-alpha/ and team-beta/\"; echo \"Create merged stack in merged/\"; exec bash'" > /tmp/terminal.log 2>&1 &
sleep 5

take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="