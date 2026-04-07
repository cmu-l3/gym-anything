#!/bin/bash
# Setup script for docker_incident_rca task
# Creates a fragile Docker Compose stack and intentionally crashes it via connection exhaustion.

set -e
echo "=== Setting up Docker Incident RCA Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Wait for Docker
if ! type wait_for_docker &>/dev/null; then
    wait_for_docker() {
        for i in {1..60}; do
            if docker info > /dev/null 2>&1; then return 0; fi
            sleep 2
        done; return 1
    }
fi
wait_for_docker

# 1. Create Project Directory
PROJECT_DIR="/home/ga/projects/store-app"
mkdir -p "$PROJECT_DIR/app" "$PROJECT_DIR/worker" "$PROJECT_DIR/nginx"
chown -R ga:ga "$PROJECT_DIR"

# 2. Create Application Code (Fragile Flask App)
cat > "$PROJECT_DIR/app/requirements.txt" <<EOF
flask==3.0.0
sqlalchemy==2.0.23
psycopg2-binary==2.9.9
EOF

cat > "$PROJECT_DIR/app/app.py" <<'EOF'
import os
import time
import logging
from flask import Flask, jsonify
from sqlalchemy import create_engine, text

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)

# Fragile configuration: defaults to greedy pool if not restricted
DB_URI = os.environ.get("DATABASE_URL", "postgresql://storeuser:storepass@store-db:5432/storedb")
engine = create_engine(DB_URI)

@app.route('/api/health')
def health():
    try:
        # Attempt to grab a connection
        with engine.connect() as conn:
            conn.execute(text("SELECT 1"))
        return jsonify({"status": "healthy"}), 200
    except Exception as e:
        logging.error(f"Health check failed: {e}")
        # Crash the container on DB failure to simulate critical dependency
        os._exit(1)

if __name__ == "__main__":
    app.run(host='0.0.0.0', port=5000)
EOF

cat > "$PROJECT_DIR/app/Dockerfile" <<EOF
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
CMD ["python", "app.py"]
EOF

# 3. Create Worker Code (Fragile Worker)
cat > "$PROJECT_DIR/worker/Dockerfile" <<EOF
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
CMD ["python", "worker.py"]
EOF

cp "$PROJECT_DIR/app/requirements.txt" "$PROJECT_DIR/worker/requirements.txt"

cat > "$PROJECT_DIR/worker/worker.py" <<'EOF'
import os
import time
import logging
from sqlalchemy import create_engine, text

logging.basicConfig(level=logging.INFO)
DB_URI = os.environ.get("DATABASE_URL", "postgresql://storeuser:storepass@store-db:5432/storedb")
engine = create_engine(DB_URI)

def do_work():
    logging.info("Worker starting...")
    retries = 0
    while True:
        try:
            with engine.connect() as conn:
                conn.execute(text("SELECT 1"))
            logging.info("Job processed")
            time.sleep(2)
        except Exception as e:
            logging.error(f"Worker connection failed: {e}")
            retries += 1
            if retries > 3:
                logging.critical("Max retries exceeded. Exiting.")
                os._exit(1) # Crash
            time.sleep(1)

if __name__ == "__main__":
    do_work()
EOF

# 4. Create Nginx Config
cat > "$PROJECT_DIR/nginx/nginx.conf" <<'EOF'
events { worker_connections 1024; }
http {
    server {
        listen 80;
        location /api/ {
            proxy_pass http://store-api:5000;
            proxy_connect_timeout 2s;
        }
    }
}
EOF

# 5. Create Vulnerable Docker Compose File
# Root Cause: max_connections=5 is WAY too low
cat > "$PROJECT_DIR/docker-compose.yml" <<'EOF'
version: '3.8'

services:
  store-db:
    image: postgres:14
    environment:
      POSTGRES_USER: storeuser
      POSTGRES_PASSWORD: storepass
      POSTGRES_DB: storedb
    # ROOT CAUSE: This limit is too low
    command: postgres -c max_connections=5
    networks:
      - store-net
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U storeuser"]
      interval: 5s
      timeout: 5s
      retries: 5

  store-api:
    build: ./app
    environment:
      DATABASE_URL: postgresql://storeuser:storepass@store-db:5432/storedb
    depends_on:
      - store-db
    networks:
      - store-net
    restart: on-failure:3

  store-worker:
    build: ./worker
    environment:
      DATABASE_URL: postgresql://storeuser:storepass@store-db:5432/storedb
    depends_on:
      - store-db
    networks:
      - store-net
    restart: on-failure:3

  store-web:
    image: nginx:1.24-alpine
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
    ports:
      - "8080:80"
    depends_on:
      - store-api
    networks:
      - store-net

networks:
  store-net:
EOF

# 6. Build and Start the Stack
echo "Building and starting stack..."
cd "$PROJECT_DIR"
docker compose build
docker compose up -d

# 7. TRIGGER THE CRASH (Load Generation)
echo "Generating traffic to trigger connection exhaustion..."

# Create a python script to spam connections
cat > /tmp/crash_gen.py <<'EOF'
import threading
import time
import socket

def attack():
    try:
        # Just open raw sockets to Postgres to eat slots rapidly
        # or hit the API which opens DB connections
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(2)
        s.connect(('localhost', 8080))
        s.send(b"GET /api/health HTTP/1.1\r\nHost: localhost\r\n\r\n")
        resp = s.recv(1024)
        s.close()
    except:
        pass

threads = []
print("Spamming connections...")
for i in range(50):
    t = threading.Thread(target=attack)
    t.start()
    threads.append(t)
    time.sleep(0.05)

for t in threads:
    t.join()
EOF

# Wait for DB to be up initially
sleep 5

# Run the crash generator inside a container attached to the network to ensure direct DB access if needed
# Actually, hitting the API via host port 8080 is sufficient if the API is greedy
python3 /tmp/crash_gen.py &

# Also spin up a 'rogue' container that eats DB connections directly to guarantee the crash
docker run -d --name connection-eater --network store-app_store-net postgres:14 \
    bash -c "for i in {1..10}; do psql postgresql://storeuser:storepass@store-db:5432/storedb -c 'SELECT pg_sleep(20)' & done; sleep 30" >/dev/null 2>&1

echo "Waiting for cascade failure..."
sleep 15

# 8. Ensure everything is Dead/Exited
echo "Stopping any survivors to ensure clean 'Exited' state for task start..."
docker stop store-web store-api store-worker store-db connection-eater 2>/dev/null || true
docker rm -f connection-eater 2>/dev/null || true

# Verify state
echo "Container states:"
docker ps -a --format "table {{.Names}}\t{{.Status}}" | grep store-

# 9. Cleanup & Prep for User
chown -R ga:ga "$PROJECT_DIR"
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# Record Start Time
date +%s > /tmp/task_start_timestamp

# Open Terminal
su - ga -c "DISPLAY=:1 gnome-terminal --maximize -- bash -c 'cd ~/projects/store-app && echo \"CRITICAL INCIDENT: E-Commerce Store is DOWN.\"; echo \"All services have crashed.\"; echo \"Check logs with: docker logs store-db (etc)\"; echo; ls -la; exec bash'" > /tmp/incident_terminal.log 2>&1 &

sleep 3
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="