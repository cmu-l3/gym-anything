#!/bin/bash
# Setup script for docker_state_extraction task
# Creates a "mystery" container modified in-place to simulate a lost Dockerfile scenario.

set -e
echo "=== Setting up Docker State Extraction Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Wait for Docker
if ! type wait_for_docker &>/dev/null; then
    wait_for_docker() {
        for i in {1..60}; do
            if docker info > /dev/null 2>&1; then return 0; fi
            sleep 2
        done
        return 1
    }
fi
wait_for_docker

# 2. Cleanup previous runs
echo "Cleaning up..."
docker rm -f acme-legacy-app 2>/dev/null || true
docker rmi acme-legacy-app:restored 2>/dev/null || true
rm -rf /home/ga/projects/acme-legacy-app
mkdir -p /home/ga/projects/acme-legacy-app
mkdir -p /home/ga/Desktop
chown -R ga:ga /home/ga/projects /home/ga/Desktop

# 3. Create Application Files in /tmp for injection
echo "Creating application artifacts..."
TEMP_DIR=$(mktemp -d)

# Python Flask App
cat > "$TEMP_DIR/inventory_api.py" << 'PYTHON_EOF'
import os
import sqlite3
from flask import Flask, jsonify, request

app = Flask(__name__)

# Config from env or file
DB_PATH = os.environ.get('DATABASE_URL', '/app/data/inventory.db').replace('sqlite:///', '')
APP_ENV = os.environ.get('APP_ENV', 'development')

@app.route('/health')
def health():
    return jsonify({
        "status": "healthy", 
        "env": APP_ENV,
        "database": "connected" if os.path.exists(DB_PATH) else "disconnected"
    })

@app.route('/api/products', methods=['GET'])
def list_products():
    try:
        conn = sqlite3.connect(DB_PATH)
        cur = conn.cursor()
        cur.execute("SELECT * FROM products")
        rows = cur.fetchall()
        return jsonify([{"id": r[0], "name": r[1], "price": r[2]} for r in rows])
    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 8000))
    app.run(host='0.0.0.0', port=port)
PYTHON_EOF

# Config JSON
cat > "$TEMP_DIR/config.json" << 'JSON_EOF'
{
    "logging": "INFO",
    "feature_flags": {
        "beta_ui": true
    },
    "maintenance_mode": false
}
JSON_EOF

# Startup Script
cat > "$TEMP_DIR/start.sh" << 'SH_EOF'
#!/bin/bash
# Acme Legacy App Startup
echo "Starting application in $APP_ENV mode..."
exec gunicorn --bind 0.0.0.0:${PORT:-8000} --workers 2 inventory_api:app
SH_EOF
chmod +x "$TEMP_DIR/start.sh"

# SQLite Database
echo "Creating SQLite database..."
python3 -c "
import sqlite3
conn = sqlite3.connect('$TEMP_DIR/inventory.db')
c = conn.cursor()
c.execute('CREATE TABLE products (id INTEGER PRIMARY KEY, name TEXT, price REAL)')
c.execute(\"INSERT INTO products VALUES (1, 'Widget A', 19.99)\")
c.execute(\"INSERT INTO products VALUES (2, 'Gadget B', 42.50)\")
c.execute(\"INSERT INTO products VALUES (3, 'Super Gizmo', 99.99)\")
conn.commit()
conn.close()
"

# 4. Start the Base Container
# We use python:3.11-slim as base, but start it with sleep infinity so we can modify it
echo "Starting base container..."
docker run -d \
    --name acme-legacy-app \
    -p 8088:8000 \
    -e APP_ENV=production \
    -e DATABASE_URL="sqlite:////app/data/inventory.db" \
    -e SECRET_KEY="acme-prod-key-2024" \
    -e PORT=8000 \
    python:3.11-slim \
    sleep infinity

# 5. Apply "In-Place" Modifications (The Forensics Targets)
echo "Applying in-place modifications..."

# A. Install System Packages
docker exec acme-legacy-app apt-get update
docker exec acme-legacy-app apt-get install -y curl vim sqlite3 procps

# B. Install Python Packages
docker exec acme-legacy-app pip install flask==3.0.0 gunicorn==21.2.0 requests==2.31.0

# C. Setup App Directory and User
docker exec acme-legacy-app useradd -m appuser
docker exec acme-legacy-app mkdir -p /app/data

# D. Inject Files
docker cp "$TEMP_DIR/inventory_api.py" acme-legacy-app:/app/
docker cp "$TEMP_DIR/config.json" acme-legacy-app:/app/
docker cp "$TEMP_DIR/start.sh" acme-legacy-app:/app/
docker cp "$TEMP_DIR/inventory.db" acme-legacy-app:/app/data/

# E. Set Permissions
docker exec acme-legacy-app chown -R appuser:appuser /app
docker exec acme-legacy-app chmod +x /app/start.sh

# 6. Start the Application INSIDE the running container
# This effectively makes it a "running application container" without using a Dockerfile
echo "Starting application process inside container..."
docker exec -d -w /app -u appuser acme-legacy-app /bin/bash -c "nohup ./start.sh > app.log 2>&1 &"

# 7. Record Verification State
date +%s > /tmp/task_start_timestamp

# Wait for app to be responsive
echo "Waiting for internal app health..."
for i in {1..10}; do
    if docker exec acme-legacy-app curl -s http://localhost:8000/health >/dev/null; then
        echo "App is healthy."
        break
    fi
    sleep 1
done

# 8. Setup Agent Environment
# Provide a terminal for the agent
su - ga -c "DISPLAY=:1 gnome-terminal --maximize -- bash -c 'echo \"Legacy Container Incident\"; echo \"Container acme-legacy-app is running.\"; echo \"Goal: Reverse engineer it into a Dockerfile.\"; echo; docker ps; exec bash'" > /tmp/terminal.log 2>&1 &

# Take screenshot
if type take_screenshot &>/dev/null; then
    take_screenshot /tmp/task_start.png
else
    DISPLAY=:1 scrot /tmp/task_start.png 2>/dev/null || true
fi

# Cleanup temp files
rm -rf "$TEMP_DIR"

echo "=== Setup Complete ==="