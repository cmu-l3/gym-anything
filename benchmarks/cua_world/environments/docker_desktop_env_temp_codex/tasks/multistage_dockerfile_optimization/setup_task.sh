#!/bin/bash
echo "=== Setting up multistage_dockerfile_optimization ==="

source /workspace/scripts/task_utils.sh

if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type wait_for_docker_daemon &>/dev/null; then
    wait_for_docker_daemon() {
        local timeout="${1:-60}"
        local i=0
        while [ $i -lt $timeout ]; do
            timeout 5 docker info >/dev/null 2>&1 && return 0
            sleep 2; i=$((i+2))
        done
        return 1
    }
fi

wait_for_docker_daemon 60

APP_DIR="/home/ga/todo-app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/src"

# --- Real Node.js Todo application (Docker's getting-started app) ---
# Source: https://github.com/docker/getting-started-app (official Docker tutorial)

cat > "$APP_DIR/package.json" << 'EOF'
{
  "name": "getting-started",
  "version": "1.0.0",
  "description": "A simple todo app based on Docker's getting started tutorial",
  "main": "src/index.js",
  "scripts": {
    "start": "node src/index.js",
    "test": "jest --coverage"
  },
  "dependencies": {
    "express": "^4.18.2",
    "uuid": "^9.0.0",
    "better-sqlite3": "^9.4.3"
  },
  "devDependencies": {
    "jest": "^29.7.0",
    "supertest": "^6.3.4",
    "nodemon": "^3.0.2",
    "eslint": "^8.56.0"
  }
}
EOF

cat > "$APP_DIR/src/index.js" << 'EOF'
const express = require('express');
const { v4: uuidv4 } = require('uuid');
const Database = require('better-sqlite3');
const path = require('path');
const fs = require('fs');

const app = express();
const PORT = process.env.PORT || 3000;

// Ensure data directory
const dataDir = process.env.DATA_DIR || './data';
if (!fs.existsSync(dataDir)) fs.mkdirSync(dataDir, { recursive: true });

const db = new Database(path.join(dataDir, 'todo.db'));

// Create table
db.exec(`CREATE TABLE IF NOT EXISTS todo_items (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    completed INTEGER NOT NULL DEFAULT 0
)`);

app.use(express.json());
app.use(express.static(path.join(__dirname, 'static')));

app.get('/api/items', (req, res) => {
    const items = db.prepare('SELECT * FROM todo_items').all();
    res.json(items);
});

app.post('/api/items', (req, res) => {
    const { name } = req.body;
    if (!name) return res.status(400).json({ error: 'name required' });
    const item = { id: uuidv4(), name, completed: 0 };
    db.prepare('INSERT INTO todo_items VALUES (?, ?, ?)').run(item.id, item.name, item.completed);
    res.status(201).json(item);
});

app.put('/api/items/:id', (req, res) => {
    const { completed } = req.body;
    const info = db.prepare('UPDATE todo_items SET completed=? WHERE id=?').run(completed ? 1 : 0, req.params.id);
    if (info.changes === 0) return res.status(404).json({ error: 'not found' });
    res.json({ updated: true });
});

app.delete('/api/items/:id', (req, res) => {
    db.prepare('DELETE FROM todo_items WHERE id=?').run(req.params.id);
    res.json({ deleted: true });
});

app.get('/health', (req, res) => {
    res.json({ status: 'ok', service: 'todo-app', version: '1.0.0' });
});

app.listen(PORT, '0.0.0.0', () => {
    console.log(`Todo app listening on port ${PORT}`);
});
EOF

mkdir -p "$APP_DIR/src/static"
cat > "$APP_DIR/src/static/index.html" << 'EOF'
<!DOCTYPE html>
<html>
<head><title>Todo App</title></head>
<body>
<h1>Todo Application</h1>
<p>API available at /api/items</p>
<p>Health check: <a href="/health">/health</a></p>
</body>
</html>
EOF

# --- Intentionally bloated single-stage Dockerfile ---
# This is the kind of Dockerfile developers write before learning multi-stage builds.
# It installs dev dependencies into the final image and uses a full OS base.
cat > "$APP_DIR/Dockerfile" << 'EOF'
# Single-stage build — installs everything including dev dependencies
# This produces a large image (>1GB) which is wasteful for production
FROM node:20

WORKDIR /usr/src/app

# Copy package files
COPY package*.json ./

# Install ALL dependencies (including devDependencies)
RUN npm install

# Copy source code
COPY . .

# Install global dev tools (adds more bloat)
RUN npm install -g nodemon eslint

# Expose port
EXPOSE 3000

# Start the application
CMD ["node", "src/index.js"]
EOF

# --- Build the original bloated image ---
echo "Building original single-stage image (this may take a few minutes)..."
cd "$APP_DIR"
docker build -t todo-app:original . 2>&1 | tail -5

# Record original image size in MB
ORIGINAL_SIZE_BYTES=$(docker inspect todo-app:original --format='{{.Size}}' 2>/dev/null || echo "0")
ORIGINAL_SIZE_MB=$((ORIGINAL_SIZE_BYTES / 1048576))
echo "$ORIGINAL_SIZE_MB" > /tmp/original_image_size_mb
echo "Original image size: ${ORIGINAL_SIZE_MB}MB"

# Remove optimized tag if it exists from previous runs
docker rmi todo-app:optimized 2>/dev/null || true

# Record Dockerfile mtime as baseline
DOCKERFILE_MTIME=$(stat -c %Y "$APP_DIR/Dockerfile" 2>/dev/null || echo "0")
echo "$DOCKERFILE_MTIME" > /tmp/initial_dockerfile_mtime

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

chown -R ga:ga "$APP_DIR"
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "App at $APP_DIR"
echo "Original image 'todo-app:original' built (${ORIGINAL_SIZE_MB}MB)"
echo "Task: rewrite Dockerfile as multi-stage build, build as 'todo-app:optimized'"
