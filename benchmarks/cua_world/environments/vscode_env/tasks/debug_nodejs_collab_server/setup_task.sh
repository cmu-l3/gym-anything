#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up Node.js Collab Server Task ==="

WORKSPACE_DIR="/home/ga/workspace/collab_server"
sudo -u ga mkdir -p "$WORKSPACE_DIR/src/utils"
sudo -u ga mkdir -p "$WORKSPACE_DIR/tests"
cd "$WORKSPACE_DIR"

# ─────────────────────────────────────────────────────────────
# 1. Write Package.json
# ─────────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/package.json" << 'EOF'
{
  "name": "collab-server",
  "version": "1.0.0",
  "description": "Real-time document collaboration server",
  "main": "src/server.js",
  "scripts": {
    "start": "node src/server.js",
    "test:load": "node tests/test_load.js"
  },
  "dependencies": {
    "ws": "^8.13.0"
  }
}
EOF

# ─────────────────────────────────────────────────────────────
# 2. Bug 1: Memory Leak (ConnectionManager.js)
# ─────────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/src/ConnectionManager.js" << 'EOF'
class ConnectionManager {
    constructor() {
        this.clients = new Set();
    }

    addClient(ws) {
        this.clients.add(ws);
    }

    removeClient(ws) {
        // BUG: Failing to delete the client from the set causes a memory leak
        ws.close();
    }

    get connectedCount() {
        return this.clients.size;
    }
}
module.exports = ConnectionManager;
EOF

# ─────────────────────────────────────────────────────────────
# 3. Bug 2: Event Loop Block (DocumentProcessor.js)
# ─────────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/src/DocumentProcessor.js" << 'EOF'
const zlib = require('zlib');

class DocumentProcessor {
    async compress(data) {
        // BUG: Synchronous compression blocks the main event loop thread
        // This causes ping timeouts for all other connected users.
        return zlib.gzipSync(Buffer.from(data));
    }
}
module.exports = DocumentProcessor;
EOF

# ─────────────────────────────────────────────────────────────
# 4. Bug 3: Race Condition (Storage.js)
# ─────────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/src/Storage.js" << 'EOF'
const TaskQueue = require('./utils/TaskQueue');

class Storage {
    constructor() {
        this.db = {};
        // Hint: A TaskQueue is available but unused!
        this.queue = new TaskQueue();
    }

    async saveDocument(id, data, simulatedDelayMs = 50) {
        // BUG: Concurrent saves will resolve out of order depending on their delay.
        // Needs to be queued to ensure chronological consistency.
        await new Promise(resolve => setTimeout(resolve, simulatedDelayMs));
        this.db[id] = data;
    }

    getDocument(id) {
        return this.db[id];
    }
}
module.exports = Storage;
EOF

cat > "$WORKSPACE_DIR/src/utils/TaskQueue.js" << 'EOF'
class TaskQueue {
    constructor() {
        this.queue = Promise.resolve();
    }

    enqueue(task) {
        this.queue = this.queue.then(() => task()).catch(console.error);
        return this.queue;
    }
}
module.exports = TaskQueue;
EOF

# ─────────────────────────────────────────────────────────────
# 5. Bug 4: Unhandled Promise Rejection (server.js & Auth.js)
# ─────────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/src/Auth.js" << 'EOF'
class Auth {
    static async verify(token) {
        if (!token || token === 'invalid') {
            throw new Error("Invalid authentication token provided!");
        }
        return { userId: "user_" + Math.random().toString(36).substr(2, 5) };
    }
}
module.exports = Auth;
EOF

cat > "$WORKSPACE_DIR/src/server.js" << 'EOF'
const WebSocket = require('ws');
const Auth = require('./Auth');
const ConnectionManager = require('./ConnectionManager');

const wss = new WebSocket.Server({ port: 8080 });
const cm = new ConnectionManager();

wss.on('connection', (ws) => {
    cm.addClient(ws);

    ws.on('message', async (message) => {
        try {
            const data = JSON.parse(message);
            
            if (data.type === 'auth') {
                // BUG: If Auth.verify throws, it causes an UnhandledPromiseRejection
                // which crashes the entire Node.js process. Needs try/catch.
                await Auth.verify(data.token);
                ws.send(JSON.stringify({ status: 'authenticated' }));
            }
        } catch (e) {
            // This only catches JSON parse errors, not the async Auth.verify error!
            console.error("Parse error:", e.message);
        }
    });

    ws.on('close', () => {
        cm.removeClient(ws);
    });
});

console.log("Collab Server running on port 8080");
module.exports = { wss, cm };
EOF

# ─────────────────────────────────────────────────────────────
# 6. Bug 5: ReDoS (Mentions.js)
# ─────────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/src/Mentions.js" << 'EOF'
class Mentions {
    static extract(text) {
        // BUG: Catastrophic backtracking vulnerability (ReDoS)
        // A long string of valid characters ending in an invalid character will peg the CPU.
        const regex = /^@([a-zA-Z0-9_]+)*!/;
        const match = text.match(regex);
        return match ? match[1] : null;
    }
}
module.exports = Mentions;
EOF

# ─────────────────────────────────────────────────────────────
# 7. Test Script for the Agent
# ─────────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/tests/test_load.js" << 'EOF'
console.log("Run this script to observe the symptoms, then fix the bugs in src/.");
console.log("When you are done, this script should complete without crashing or hanging.\n");
// In a real scenario, this would generate load. For this task, it's just a placeholder.
console.log("Testing memory...");
console.log("Testing event loop...");
console.log("Testing concurrency...");
console.log("Testing resilience...");
console.log("\nReview the README_SYMPTOMS.md for details!");
EOF

cat > "$WORKSPACE_DIR/README_SYMPTOMS.md" << 'EOF'
# Production Symptoms

1. **Memory Growth:** The server runs out of memory over time.
2. **Ping Timeouts:** When a user triggers a compression snapshot, other users lag.
3. **Data Overwrites:** Concurrent typing saves occasionally arrive out of order.
4. **Random Crashes:** The server process occasionally exits completely when auth fails.
5. **CPU Spikes:** Chat messages with many '@' symbols freeze the server.
EOF

# Install dependencies and setup Git
sudo -u ga npm install
sudo -u ga git init
sudo -u ga git add .
sudo -u ga git commit -m "Initial buggy commit"

# Set permissions
chown -R ga:ga "$WORKSPACE_DIR"

# Launch VSCode
echo "Launching VS Code..."
sudo -u ga DISPLAY=:1 code "$WORKSPACE_DIR"
sleep 5

# Maximize and Focus
WID=$(wmctrl -l | grep -i "Visual Studio Code" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    wmctrl -ia "$WID"
    wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz
fi

# Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

# Record task start time
date +%s > /tmp/task_start_time.txt

echo "=== Setup complete ==="