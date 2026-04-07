#!/bin/bash
set -e

# Import utils
source /workspace/scripts/task_utils.sh || true

echo "=== Setting up Polyglot Debug Config Task ==="

# Record start time
date +%s > /tmp/task_start_time.txt

WORKSPACE_DIR="/home/ga/workspace/media_pipeline"
sudo -u ga mkdir -p "$WORKSPACE_DIR/api"
sudo -u ga mkdir -p "$WORKSPACE_DIR/worker"
sudo -u ga mkdir -p "$WORKSPACE_DIR/data"

# Install Redis server and Node/Python dependencies
echo "Installing dependencies..."
apt-get update -qq && apt-get install -y -qq redis-server > /dev/null
# Ensure redis is not running as a daemon so the agent's VS Code task can bind to port 6379
systemctl stop redis-server 2>/dev/null || true  
npm install -g redis sqlite3 > /dev/null 2>&1 || true
pip3 install redis fastapi uvicorn > /dev/null 2>&1 || true

# 1. Generate Dataset
cat > "$WORKSPACE_DIR/data/podcast_episodes.json" << 'EOF'
[
  {"id": "ep1", "title": "Tech Today", "description": "Latest tech news."},
  {"id": "ep2", "title": "Science Weekly", "description": "Discoveries and more."},
  {"id": "ep3", "title": "History Hour", "description": null},
  {"id": "ep4", "title": "Daily Meditations", "description": "Relax your mind."},
  {"id": "ep5", "title": "Mystery Show", "description": null}
]
EOF

# 2. Python API (api/main.py)
cat > "$WORKSPACE_DIR/api/main.py" << 'EOF'
import sqlite3
import redis
import json
import time

def setup_db():
    conn = sqlite3.connect('../podcast.db')
    conn.execute('CREATE TABLE IF NOT EXISTS episodes (id TEXT PRIMARY KEY, title TEXT, description TEXT)')
    conn.commit()
    conn.close()

def process_upload(record):
    r = redis.Redis(host='localhost', port=6379, db=0)
    conn = sqlite3.connect('../podcast.db')
    cursor = conn.cursor()
    
    cursor.execute(
        'INSERT OR REPLACE INTO episodes (id, title, description) VALUES (?, ?, ?)', 
        (record['id'], record['title'], record['description'])
    )
    
    # BUG: Race condition! Publishing to Redis BEFORE committing to the database.
    # The worker might pick up the job and query the DB before the transaction is committed.
    r.publish('new_episode', json.dumps({'id': record['id']}))
    
    # Artificial delay to guarantee the race condition fails in testing if not fixed
    time.sleep(0.5) 
    
    conn.commit()
    conn.close()

if __name__ == "__main__":
    setup_db()
    print("Python API started. Processing mock records...")
    with open('../data/podcast_episodes.json', 'r') as f:
        data = json.load(f)
        for record in data:
            process_upload(record)
            print(f"Processed {record['id']}")
            time.sleep(1)
EOF

# 3. Node Worker (worker/processor.js)
cat > "$WORKSPACE_DIR/worker/processor.js" << 'EOF'
const redis = require('redis');
const sqlite3 = require('sqlite3').verbose();

const subscriber = redis.createClient({ url: 'redis://localhost:6379' });
const db = new sqlite3.Database('../podcast.db');

subscriber.on('error', (err) => console.error('Redis Client Error', err));

async function start() {
    await subscriber.connect();
    console.log("Node worker started. Listening for 'new_episode' events...");
    
    await subscriber.subscribe('new_episode', (message) => {
        const data = JSON.parse(message);
        
        db.get('SELECT * FROM episodes WHERE id = ?', [data.id], (err, row) => {
            if (err) {
                console.error('DB Error:', err);
                return;
            }
            if (!row) {
                console.error('Record Not Found in DB (Race Condition!):', data.id);
                return;
            }
            
            // BUG: Null reference crash if description is null
            let desc = row.description;
            let descLength = desc.length; // Crashes here if desc is null
            
            console.log(`Processed episode ${row.id}. Description length: ${descLength}`);
        });
    });
}

start();
EOF

# Fix permissions
chown -R ga:ga "$WORKSPACE_DIR"
cd "$WORKSPACE_DIR/worker"
sudo -u ga npm init -y > /dev/null
sudo -u ga npm install redis sqlite3 > /dev/null

# Open VSCode
if ! pgrep -f "code.*media_pipeline" > /dev/null; then
    sudo -u ga DISPLAY=:1 code "$WORKSPACE_DIR" &
    sleep 5
fi

# Wait for VSCode window and maximize it
DISPLAY=:1 wmctrl -r "Visual Studio Code" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Visual Studio Code" 2>/dev/null || true

# Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="