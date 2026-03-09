#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Event Listener Memory Leak Diagnosis Task ==="

PROJECT_DIR="/home/ga/workspace/memory-leak-project"
SRC_DIR="$PROJECT_DIR/src"

# Create project structure
sudo -u ga mkdir -p "$SRC_DIR"

# Create the buggy websocket handler with memory leak
cat > "$SRC_DIR/websocket-handler.js" << 'EOF'
// WebSocket connection handler with memory leak
const EventEmitter = require('events');

class WebSocketHandler extends EventEmitter {
  constructor() {
    super();
    this.connections = new Map();
    this.messageCount = 0;
  }

  handleNewConnection(ws, connectionId) {
    console.log(`New connection: ${connectionId}`);
    this.connections.set(connectionId, ws);

    // BUG: These listeners are never removed!
    ws.on('message', (data) => {
      this.messageCount++;
      this.emit('messageReceived', { connectionId, data });
      console.log(`Message from ${connectionId}: ${data}`);
    });

    ws.on('error', (err) => {
      console.error(`Error on connection ${connectionId}:`, err);
      this.emit('connectionError', { connectionId, error: err });
    });

    // BUG: Ping handler also leaks - interval never cleared
    const pingInterval = setInterval(() => {
      if (ws.readyState === 1) {
        ws.ping();
      }
    }, 30000);

    // BUG: Close handler doesn't clean up properly
    ws.on('close', () => {
      console.log(`Connection closed: ${connectionId}`);
      this.connections.delete(connectionId);
      // Missing: listener removal, interval clearance
    });
  }

  broadcast(message) {
    for (const [id, ws] of this.connections) {
      if (ws.readyState === 1) {
        ws.send(message);
      }
    }
  }

  getStats() {
    return {
      activeConnections: this.connections.size,
      totalMessages: this.messageCount
    };
  }
}

module.exports = WebSocketHandler;
EOF

# Create README with context
cat > "$PROJECT_DIR/README.md" << 'EOF'
# WebSocket Memory Leak Investigation

## Problem
The service memory usage grows ~50MB per 100 connections. DevOps reports increasing RAM consumption in production Kubernetes pods (now 2GB instead of expected 300MB).

**Root cause**: Event listener memory leak in WebSocket handler.

## Files
- `src/websocket-handler.js` - **Main handler (FIX THIS FILE!)**
- `src/server.js` - Server setup (for context)
- `package.json` - Dependencies

## Your Task
Fix the memory leak by ensuring all event listeners and timers are properly cleaned up when connections close.

## What to look for
1. Event listeners registered with `.on()` that are never removed
2. Intervals created with `setInterval()` that are never cleared
3. The close handler that needs cleanup logic added

## How to fix
- Use `.removeAllListeners('eventName')` or `.removeListener('eventName', handler)`
- Use `clearInterval(intervalId)` to stop timers
- Ensure cleanup happens in the 'close' event handler
EOF

# Create package.json
cat > "$PROJECT_DIR/package.json" << 'EOF'
{
  "name": "websocket-service",
  "version": "1.0.0",
  "description": "WebSocket service with memory leak to fix",
  "main": "src/server.js",
  "dependencies": {
    "ws": "^8.13.0"
  },
  "scripts": {
    "start": "node src/server.js"
  }
}
EOF

# Create server.js for context
cat > "$SRC_DIR/server.js" << 'EOF'
const WebSocket = require('ws');
const WebSocketHandler = require('./websocket-handler');

const wss = new WebSocket.Server({ port: 8080 });
const handler = new WebSocketHandler();

let connectionId = 0;

wss.on('connection', (ws) => {
  handler.handleNewConnection(ws, `conn-${connectionId++}`);
});

console.log('WebSocket server running on port 8080');
console.log('Monitoring for memory leaks...');

// Log stats every 30 seconds
setInterval(() => {
  const stats = handler.getStats();
  console.log(`Stats: ${JSON.stringify(stats)}`);
}, 30000);
EOF

# Set ownership
sudo chown -R ga:ga "$PROJECT_DIR"

# Open VSCode with the project
echo "Opening VSCode with project..."
su - ga -c "DISPLAY=:1 code '$PROJECT_DIR'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

# Open the problematic file directly
sleep 1
su - ga -c "DISPLAY=:1 code '$SRC_DIR/websocket-handler.js'" || true
sleep 2

echo "=== Event Listener Memory Leak Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Review websocket-handler.js (should already be open)"
echo "  2. Find event listeners registered with .on() but never removed"
echo "  3. Find the setInterval that is never cleared"
echo "  4. Add cleanup in the 'close' event handler:"
echo "     - ws.removeAllListeners('message')"
echo "     - ws.removeAllListeners('error')"
echo "     - clearInterval(pingInterval)"
echo "  5. Save the file (Ctrl+S)"