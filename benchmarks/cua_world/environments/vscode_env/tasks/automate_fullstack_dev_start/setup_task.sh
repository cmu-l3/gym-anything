#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Automate Full-Stack Dev Start Task ==="

WORKSPACE_DIR="/home/ga/workspace/fullstack-project"

# Create directory structure
echo "Creating project structure..."
sudo -u ga mkdir -p "$WORKSPACE_DIR"/{backend/migrations,frontend,scripts,.vscode}

# Create backend server
cat > "$WORKSPACE_DIR/backend/server.py" << 'EOF'
#!/usr/bin/env python3
"""Simple Flask server for development"""
from flask import Flask, jsonify
import os
import sys

app = Flask(__name__)

@app.route('/')
def index():
    return jsonify({
        'status': 'running',
        'env': os.getenv('APP_ENV', 'development'),
        'message': 'Full-stack dev server is live!'
    })

@app.route('/health')
def health():
    return jsonify({'status': 'healthy'})

if __name__ == '__main__':
    port = int(os.getenv('PORT', '5000'))
    env = os.getenv('APP_ENV', 'development')
    print(f"🚀 Starting server in {env} mode on port {port}...")
    print(f"📍 Server running at http://0.0.0.0:{port}")
    
    # Run server (will keep running until stopped)
    try:
        app.run(host='0.0.0.0', port=port, debug=True, use_reloader=False)
    except KeyboardInterrupt:
        print("\n👋 Server stopped")
        sys.exit(0)
EOF

chmod +x "$WORKSPACE_DIR/backend/server.py"

# Create database migration
cat > "$WORKSPACE_DIR/backend/migrations/init_db.sql" << 'EOF'
-- Initialize development database
CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT NOT NULL UNIQUE,
    email TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS sessions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER,
    token TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users (id)
);

-- Insert test data
INSERT OR IGNORE INTO users (id, username, email) VALUES 
    (1, 'test_user', 'test@example.com'),
    (2, 'dev_user', 'dev@example.com');

INSERT OR IGNORE INTO sessions (user_id, token) VALUES 
    (1, 'test_token_123');
EOF

# Create requirements.txt
cat > "$WORKSPACE_DIR/backend/requirements.txt" << 'EOF'
flask==2.3.0
Werkzeug==2.3.0
EOF

# Create cleanup script
cat > "$WORKSPACE_DIR/scripts/clean.sh" << 'EOF'
#!/bin/bash
# Cleanup development build artifacts

echo "🧹 Cleaning development environment..."
echo "  → Removing temporary build files..."

# Remove Python cache
find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
find . -type f -name "*.pyc" -delete 2>/dev/null || true
find . -type f -name "*.pyo" -delete 2>/dev/null || true

# Remove old build artifacts
rm -rf /tmp/dev-build-* 2>/dev/null || true
rm -rf /tmp/flask_session 2>/dev/null || true

# Remove old logs
rm -f /tmp/dev-server.log 2>/dev/null || true

echo "✅ Cleanup complete!"
exit 0
EOF

chmod +x "$WORKSPACE_DIR/scripts/clean.sh"

# Create database initialization script
cat > "$WORKSPACE_DIR/scripts/start_db.sh" << 'EOF'
#!/bin/bash
# Initialize development database

echo "🗄️  Initializing development database..."

DB_PATH="${DB_PATH:-/tmp/dev.db}"

# Remove old database
if [ -f "$DB_PATH" ]; then
    echo "  → Removing old database..."
    rm -f "$DB_PATH"
fi

# Create new database
echo "  → Creating database at $DB_PATH..."
sqlite3 "$DB_PATH" < backend/migrations/init_db.sql

if [ $? -eq 0 ]; then
    echo "✅ Database initialized successfully!"
    echo "   Location: $DB_PATH"
    
    # Verify tables were created
    TABLE_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM sqlite_master WHERE type='table';")
    echo "   Tables created: $TABLE_COUNT"
else
    echo "❌ Database initialization failed!"
    exit 1
fi

exit 0
EOF

chmod +x "$WORKSPACE_DIR/scripts/start_db.sh"

# Create .env.example
cat > "$WORKSPACE_DIR/.env.example" << 'EOF'
# Development Environment Variables
APP_ENV=development
PORT=5000
DB_PATH=/tmp/dev.db
DEBUG=true
EOF

# Create README with instructions
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Full-Stack Development Project

## The Problem

Every time you start development, you need to manually run:

1. `bash scripts/clean.sh` - Clean old build artifacts and caches
2. `bash scripts/start_db.sh` - Initialize SQLite database with migrations
3. `cd backend && APP_ENV=development python server.py` - Start Flask server

This is **tedious**, **error-prone**, and **frustrating** for new team members!

## The Solution

Use VSCode's built-in task system to automate this workflow.

## Your Task

Create `.vscode/tasks.json` with 4 tasks:

### Individual Tasks

1. **clean-dev**: Runs `bash scripts/clean.sh`
2. **init-database**: Runs `bash scripts/start_db.sh`
3. **start-backend**: Runs `python backend/server.py` with `APP_ENV=development`

### Compound Task

4. **start-dev-environment**: 
   - Runs all 3 tasks above **in sequence** (not parallel!)
   - Set as **default build task** (so Ctrl+Shift+B works)
   - Uses `dependsOrder: "sequence"` for sequential execution

## How to Create

1. Open Command Palette (Ctrl+Shift+P)
2. Type "Tasks: Configure Task"
3. Select "Create tasks.json from template"
4. Choose "Others"
5. Edit the generated tasks.json

## Testing

Press `Ctrl+Shift+B` to run your compound task!

## Expected Behavior

When you run the compound task:
1. ✅ Cleanup runs first
2. ✅ Database initializes
3. ✅ Server starts on port 5000
4. ✅ You see: "🚀 Starting server in development mode..."

## Current Manual Process
