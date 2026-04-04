#!/bin/bash
set -e
echo "=== Setting up Refactor Monolith task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Project Setup
PROJECT_DIR="/home/ga/legacy_project"
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"

# Create Application Code (app.py)
cat > app.py << 'EOF'
import os
import time
import psycopg2
from flask import Flask, jsonify

app = Flask(__name__)

# Configuration with defaults (agent needs to override these via env vars)
DB_HOST = os.environ.get('DB_HOST', 'localhost')
DB_NAME = os.environ.get('DB_NAME', 'notes_db')
DB_USER = os.environ.get('DB_USER', 'notes_user')
DB_PASS = os.environ.get('DB_PASS', 'notes_password')

def get_db_connection():
    conn = psycopg2.connect(
        host=DB_HOST,
        database=DB_NAME,
        user=DB_USER,
        password=DB_PASS
    )
    return conn

def init_db():
    # Retry logic to handle container startup timing
    retries = 10
    while retries > 0:
        try:
            conn = get_db_connection()
            cur = conn.cursor()
            cur.execute('CREATE TABLE IF NOT EXISTS notes (id SERIAL PRIMARY KEY, content TEXT);')
            conn.commit()
            cur.close()
            conn.close()
            print("Database initialized successfully.")
            return True
        except psycopg2.OperationalError as e:
            print(f"DB not ready yet ({e}), retrying... ({retries} left)")
            time.sleep(2)
            retries -= 1
    return False

# Initialize on startup
if not init_db():
    print("WARNING: Could not connect to database after retries.")

@app.route('/')
def index():
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute('SELECT count(*) FROM notes;')
        count = cur.fetchone()[0]
        cur.close()
        conn.close()
        return jsonify({
            "status": "healthy", 
            "service": "notes-app", 
            "db_host": DB_HOST,
            "note_count": count
        })
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

# Create Requirements
cat > requirements.txt << 'EOF'
flask==3.0.0
psycopg2-binary==2.9.9
EOF

# Create the "Bad" Monolithic Dockerfile
# We include commands to install postgresql to simulate the monolith,
# but we use a base image that exists to avoid long build times if they try to build it.
cat > Dockerfile << 'EOF'
FROM python:3.9-slim

# ANTI-PATTERN: Installing the database server inside the app container
# The agent should REMOVE this block
RUN apt-get update && apt-get install -y \
    postgresql \
    postgresql-contrib \
    libpq-dev \
    gcc \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# ANTI-PATTERN: Startup script to run both services
COPY start_monolith.sh .
RUN chmod +x start_monolith.sh

CMD ["./start_monolith.sh"]
EOF

# Create the Legacy Startup Script
cat > start_monolith.sh << 'EOF'
#!/bin/bash
echo "Starting Legacy Monolith..."
service postgresql start || echo "Warning: Postgres failed to start via service"
python app.py
EOF
chmod +x start_monolith.sh

# Fix permissions
chown -R ga:ga "$PROJECT_DIR"

# 2. Pre-pull images to speed up the task
echo "Pre-pulling images..."
docker pull python:3.9-slim >/dev/null 2>&1 || true
docker pull postgres:15-alpine >/dev/null 2>&1 || true

# 3. Ensure Docker Desktop is running
if ! docker_desktop_running; then
    echo "Starting Docker Desktop..."
    su - ga -c "DISPLAY=:1 XDG_RUNTIME_DIR=/run/user/1000 /opt/docker-desktop/bin/docker-desktop > /tmp/docker-desktop.log 2>&1 &"
    # Wait for it to start
    for i in {1..30}; do
        if docker_desktop_running; then break; fi
        sleep 1
    done
fi

# 4. Wait for Docker daemon
echo "Waiting for Docker daemon..."
wait_for_docker_daemon 60

# 5. Clean up any previous containers
docker rm -f $(docker ps -aq) 2>/dev/null || true
docker volume prune -f >/dev/null 2>&1 || true

# 6. Open Docker Desktop and Project Folder
focus_docker_desktop
su - ga -c "xdg-open $PROJECT_DIR" 2>/dev/null || true

# 7. Record start time
date +%s > /tmp/task_start_time.txt

# 8. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="