#!/bin/bash
set -e
echo "=== Setting up Docker Systemd Conversion Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Wait for Docker to be ready
wait_for_docker

# Record task start timestamp for verification
date +%s > /tmp/task_start_time.txt

# 1. Create Project Directory
PROJECT_DIR="/home/ga/projects/acme-services"
mkdir -p "$PROJECT_DIR/api"
mkdir -p "$PROJECT_DIR/frontend"

# 2. Create Dummy Application Code
# API (Flask)
cat > "$PROJECT_DIR/api/app.py" << 'EOF'
import os
import time
from flask import Flask, jsonify
import psycopg2

app = Flask(__name__)

@app.route('/health')
def health():
    # Check DB connection
    db_host = os.environ.get('DB_HOST', 'acme-db')
    try:
        conn = psycopg2.connect(
            host=db_host,
            database=os.environ.get('POSTGRES_DB', 'acmedb'),
            user=os.environ.get('POSTGRES_USER', 'acmeuser'),
            password=os.environ.get('POSTGRES_PASSWORD', 'secretpass')
        )
        conn.close()
        db_status = "connected"
    except Exception as e:
        db_status = f"failed: {str(e)}"
    
    return jsonify({"status": "ok", "db": db_status})

@app.route('/')
def index():
    return "Acme API v1.0"

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

cat > "$PROJECT_DIR/api/requirements.txt" << 'EOF'
flask
psycopg2-binary
EOF

cat > "$PROJECT_DIR/api/Dockerfile" << 'EOF'
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
CMD ["python", "app.py"]
EOF

# Frontend (Nginx)
cat > "$PROJECT_DIR/frontend/nginx.conf" << 'EOF'
server {
    listen 80;
    location / {
        proxy_pass http://acme-api:5000;
        proxy_set_header Host $host;
    }
    location /health {
        proxy_pass http://acme-api:5000/health;
    }
}
EOF

cat > "$PROJECT_DIR/frontend/Dockerfile" << 'EOF'
FROM nginx:1.24-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
EOF

# 3. Build Images (Pre-build so agent doesn't waste time waiting)
echo "Building initial images..."
docker build -t acme-api:latest "$PROJECT_DIR/api/"
docker build -t acme-frontend:latest "$PROJECT_DIR/frontend/"

# Pull Postgres if not present
if ! docker image inspect postgres:14 >/dev/null 2>&1; then
    docker pull postgres:14
fi

# 4. Create the manual run script (The "Messy" Starting State)
cat > "$PROJECT_DIR/run_services.sh" << 'EOF'
#!/bin/bash
# Manual startup script - DO NOT LOSE THIS!
# TODO: Move to systemd someday...

echo "Starting Acme Services..."

# Create network if missing
docker network create acme-net 2>/dev/null || true

# Start DB
echo "Starting DB..."
docker run -d \
  --name acme-db \
  --network acme-net \
  -e POSTGRES_USER=acmeuser \
  -e POSTGRES_PASSWORD=secretpass \
  -e POSTGRES_DB=acmedb \
  postgres:14

# Start API
echo "Starting API..."
docker run -d \
  --name acme-api \
  --network acme-net \
  -e DB_HOST=acme-db \
  -e POSTGRES_USER=acmeuser \
  -e POSTGRES_PASSWORD=secretpass \
  -e POSTGRES_DB=acmedb \
  acme-api:latest

# Start Frontend
echo "Starting Frontend..."
docker run -d \
  --name acme-frontend \
  --network acme-net \
  -p 8080:80 \
  acme-frontend:latest

echo "Services started!"
EOF
chmod +x "$PROJECT_DIR/run_services.sh"

# 5. Start the environment (Agent sees this running)
"$PROJECT_DIR/run_services.sh"

# Fix permissions
chown -R ga:ga "$PROJECT_DIR"

# 6. Ensure no systemd units exist yet
rm -f /etc/systemd/system/acme-*.service
systemctl daemon-reload

# 7. Setup User Environment
# Open terminal in the project directory
su - ga -c "DISPLAY=:1 gnome-terminal --maximize -- bash -c 'cd ~/projects/acme-services && echo \"Legacy Deployment Script: ./run_services.sh\"; echo \"Task: Convert this to systemd units.\"; ls -l; exec bash'" > /tmp/terminal_launch.log 2>&1 &
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="