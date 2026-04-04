#!/bin/bash
# Setup script for implement_waf_sidecar_protection

echo "=== Setting up WAF Sidecar Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Wait for Docker daemon
wait_for_docker_daemon 60

APP_DIR="/home/ga/legacy-app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR"

# 1. Create the Vulnerable Flask App
cat > "$APP_DIR/app.py" << 'PYEOF'
from flask import Flask, request, jsonify
import sqlite3

app = Flask(__name__)

def init_db():
    conn = sqlite3.connect(':memory:')
    c = conn.cursor()
    c.execute('CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT, role TEXT)')
    c.execute("INSERT INTO employees VALUES (1, 'Alice Smith', 'Manager')")
    c.execute("INSERT INTO employees VALUES (2, 'Bob Jones', 'Developer')")
    c.execute("INSERT INTO employees VALUES (3, 'Charlie Day', 'Designer')")
    conn.commit()
    return conn

# Global db connection for this simple demo
db = init_db()

@app.route('/')
def index():
    query = request.args.get('q', '')
    if not query:
        return jsonify({"message": "Welcome to HR Dashboard. Use ?q=name to search."})
    
    # VULNERABLE SQL QUERY
    # This intentionally uses string formatting to allow SQL injection
    sql = f"SELECT * FROM employees WHERE name LIKE '%{query}%'"
    
    try:
        cur = db.cursor()
        cur.execute(sql)
        results = cur.fetchall()
        return jsonify({"results": results, "query_debug": sql})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
PYEOF

# 2. Create Dockerfile
cat > "$APP_DIR/Dockerfile" << 'DOCKERFILE'
FROM python:3.9-slim
WORKDIR /app
RUN pip install flask
COPY app.py .
CMD ["python", "app.py"]
DOCKERFILE

# 3. Create initial insecure docker-compose.yml
cat > "$APP_DIR/docker-compose.yml" << 'YAML'
services:
  app:
    build: .
    container_name: legacy-app
    ports:
      - "8080:5000"
    networks:
      - internal

networks:
  internal:
YAML

# 4. Create testing artifacts for the user
cat > "$APP_DIR/traffic.txt" << 'TXT'
http://localhost:8080/?q=Alice
http://localhost:8080/?q=Bob
TXT

cat > "$APP_DIR/attacks.txt" << 'TXT'
http://localhost:8080/?q=' OR 1=1--
http://localhost:8080/?q=<script>alert(1)</script>
TXT

cat > "$APP_DIR/README.md" << 'MD'
# Legacy HR Dashboard Protection Task

This application is vulnerable to SQL Injection.

## Goal
Protect the application by adding a WAF sidecar without modifying `app.py`.

## Instructions
1. Edit `docker-compose.yml`.
2. Add a new service using the `owasp/modsecurity-crs:3-nginx` image.
3. Configure the WAF to proxy traffic to the `app` service.
   - Hint: This image uses the `BACKEND` environment variable (e.g., `BACKEND=http://app:5000`).
4. **Remove** the direct port mapping (`8080:5000`) from the `app` service.
5. Map port `8080` on the host to the WAF service instead.

## Verification
- Normal search: `curl "http://localhost:8080/?q=Alice"` -> 200 OK
- Attack: `curl "http://localhost:8080/?q=' OR 1=1"` -> 403 Forbidden
MD

# Set permissions
chown -R ga:ga "$APP_DIR"

# 5. Start the initial vulnerable stack
echo "Starting vulnerable stack..."
cd "$APP_DIR"
su - ga -c "docker compose up -d --build"

# Record start time
date +%s > /tmp/task_start_time.txt

# Pre-pull the WAF image to save time for the agent
echo "Pre-pulling WAF image..."
docker pull owasp/modsecurity-crs:3-nginx &

# Focus Docker Desktop if running
focus_docker_desktop

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="