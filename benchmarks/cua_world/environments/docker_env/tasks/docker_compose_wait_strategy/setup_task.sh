#!/bin/bash
set -e
echo "=== Setting up Docker Compose Wait Strategy Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Wait for Docker
if ! docker info >/dev/null 2>&1; then
    echo "Waiting for Docker daemon..."
    for i in {1..30}; do
        if docker info >/dev/null 2>&1; then break; fi
        sleep 2
    done
fi

# Create project directory
PROJECT_DIR="/home/ga/projects/ci-pipeline"
mkdir -p "$PROJECT_DIR/backend"
mkdir -p "$PROJECT_DIR/seeder"

# --- Create Backend Files ---
cat > "$PROJECT_DIR/backend/app.py" << 'EOF'
import os
import time
import psycopg2
from flask import Flask, jsonify

app = Flask(__name__)

def get_db_connection():
    return psycopg2.connect(
        host=os.environ.get('POSTGRES_HOST', 'db'),
        database=os.environ.get('POSTGRES_DB', 'postgres'),
        user=os.environ.get('POSTGRES_USER', 'postgres'),
        password=os.environ.get('POSTGRES_PASSWORD', 'password')
    )

@app.route('/health')
def health():
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        # Check if data seeded
        cur.execute('SELECT count(*) FROM users;')
        count = cur.fetchone()[0]
        cur.close()
        conn.close()
        
        if count > 0:
            return jsonify({"status": "healthy", "users": count}), 200
        else:
            return jsonify({"status": "unseeded", "error": "No users found"}), 503
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

cat > "$PROJECT_DIR/backend/Dockerfile" << 'EOF'
FROM python:3.9-slim
WORKDIR /app
RUN pip install flask psycopg2-binary
COPY app.py .
CMD ["python", "app.py"]
EOF

# --- Create Seeder Files ---
cat > "$PROJECT_DIR/seeder/seed.py" << 'EOF'
import os
import time
import psycopg2
import sys

def seed():
    try:
        conn = psycopg2.connect(
            host=os.environ.get('POSTGRES_HOST', 'db'),
            database=os.environ.get('POSTGRES_DB', 'postgres'),
            user=os.environ.get('POSTGRES_USER', 'postgres'),
            password=os.environ.get('POSTGRES_PASSWORD', 'password')
        )
        cur = conn.cursor()
        
        print("Creating table...")
        cur.execute('CREATE TABLE IF NOT EXISTS users (id SERIAL PRIMARY KEY, name VARCHAR(100));')
        
        print("Seeding data...")
        cur.execute('INSERT INTO users (name) VALUES (%s)', ('Alice',))
        cur.execute('INSERT INTO users (name) VALUES (%s)', ('Bob',))
        
        conn.commit()
        cur.close()
        conn.close()
        print("Seeding complete.")
        sys.exit(0)
    except Exception as e:
        print(f"Seeding failed: {e}")
        sys.exit(1)

if __name__ == '__main__':
    seed()
EOF

cat > "$PROJECT_DIR/seeder/Dockerfile" << 'EOF'
FROM python:3.9-slim
WORKDIR /app
RUN pip install psycopg2-binary
COPY seed.py .
CMD ["python", "seed.py"]
EOF

# --- Create Broken Docker Compose File ---
cat > "$PROJECT_DIR/docker-compose.yml" << 'EOF'
version: '3.8'

services:
  db:
    image: postgres:14
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: password
      POSTGRES_DB: appdb
    # MISSING: healthcheck

  seeder:
    build: ./seeder
    environment:
      POSTGRES_HOST: db
      POSTGRES_DB: appdb
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: password
    # MISSING: depends_on with condition: service_healthy

  backend:
    build: ./backend
    ports:
      - "5000:5000"
    environment:
      POSTGRES_HOST: db
      POSTGRES_DB: appdb
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: password
    # MISSING: depends_on with condition: service_completed_successfully
EOF

# Set permissions
chown -R ga:ga "$PROJECT_DIR"

# Clean up any previous run
docker rm -f $(docker ps -a -q --filter label=com.docker.compose.project=ci-pipeline) 2>/dev/null || true

# Pre-build images to save time for the agent, but verify they fail first?
# No, let the agent experience the failure or just inspect the file.
# We will pre-build to make the task faster.
echo "Pre-building images..."
cd "$PROJECT_DIR"
docker compose build

# Timestamp for verification
date +%s > /tmp/task_start_time.txt

# Initial screenshot
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop
su - ga -c "DISPLAY=:1 gnome-terminal --maximize -- bash -c 'cd ~/projects/ci-pipeline && echo \"Task: Fix race conditions in docker-compose.yml\"; echo \"Current state: Services start out of order and fail.\"; echo; ls -la; exec bash'" > /tmp/term.log 2>&1 &
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="