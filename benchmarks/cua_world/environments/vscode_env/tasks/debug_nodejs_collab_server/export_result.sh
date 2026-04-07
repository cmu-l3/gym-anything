#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Node.js Collab Server Result ==="

WORKSPACE_DIR="/home/ga/workspace/collab_server"
RESULT_FILE="/tmp/task_result.json"

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Best-effort: focus VSCode and save all open files
focus_vscode_window 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+shift+s 2>/dev/null || true
sleep 2

# Create a hidden dynamic verification script to test the agent's code
cat > "$WORKSPACE_DIR/tests/verify_hidden.js" << 'EOF'
const ConnectionManager = require('../src/ConnectionManager');
const DocumentProcessor = require('../src/DocumentProcessor');
const Storage = require('../src/Storage');
const fs = require('fs');

async function runTests() {
    const results = {
        memoryLeakFixed: false,
        eventLoopFixed: false,
        raceConditionFixed: false
    };

    // 1. Memory Leak Test
    try {
        const cm = new ConnectionManager();
        const fakeWs = { close: () => {} };
        cm.addClient(fakeWs);
        cm.removeClient(fakeWs);
        results.memoryLeakFixed = (cm.clients.size === 0);
    } catch(e) {}

    // 2. Event Loop Test
    try {
        const dp = new DocumentProcessor();
        const crypto = require('crypto');
        const largeData = crypto.randomBytes(1024 * 1024 * 5).toString('hex'); // 10MB
        
        let tickCount = 0;
        const interval = setInterval(() => tickCount++, 10);
        
        await dp.compress(largeData);
        clearInterval(interval);
        
        // If async, event loop will tick multiple times during compression
        results.eventLoopFixed = (tickCount >= 2);
    } catch(e) {}

    // 3. Race Condition Test
    try {
        const storage = new Storage();
        let p1 = storage.saveDocument('doc1', 'Version 1', 100);
        let p2 = storage.saveDocument('doc1', 'Version 2', 10);
        await Promise.all([p1, p2]);
        
        // If queued properly, Version 2 finishes last because it was enqueued last
        results.raceConditionFixed = (storage.getDocument('doc1') === 'Version 2');
    } catch(e) {}

    console.log(JSON.stringify(results));
}

runTests().catch(() => {
    console.log(JSON.stringify({ error: true }));
});
EOF

# Run the dynamic tests
DYNAMIC_TESTS=$(cd "$WORKSPACE_DIR" && node tests/verify_hidden.js 2>/dev/null || echo "{}")

# Collect source files for static verification (AST/Regex)
python3 << PYEXPORT
import json, os

workspace = "$WORKSPACE_DIR"
dynamic_tests = $DYNAMIC_TESTS

files_to_export = {
    "src/ConnectionManager.js": os.path.join(workspace, "src", "ConnectionManager.js"),
    "src/DocumentProcessor.js": os.path.join(workspace, "src", "DocumentProcessor.js"),
    "src/Storage.js":           os.path.join(workspace, "src", "Storage.js"),
    "src/server.js":            os.path.join(workspace, "src", "server.js"),
    "src/Mentions.js":          os.path.join(workspace, "src", "Mentions.js"),
}

result = {
    "dynamic_tests": dynamic_tests if isinstance(dynamic_tests, dict) else {},
    "sources": {}
}

for label, path in files_to_export.items():
    try:
        with open(path, "r", encoding="utf-8") as f:
            result["sources"][label] = f.read()
    except Exception as e:
        result["sources"][label] = ""

with open("$RESULT_FILE", "w", encoding="utf-8") as out:
    json.dump(result, out, indent=2)

PYEXPORT

echo "=== Export Complete ==="