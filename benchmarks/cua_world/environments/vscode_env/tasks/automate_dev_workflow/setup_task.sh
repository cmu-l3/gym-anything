#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Automate Dev Workflow Task ==="

WORKSPACE_DIR="/home/ga/dev-project"
sudo -u ga mkdir -p "$WORKSPACE_DIR"
cd "$WORKSPACE_DIR"

# Create package.json with npm scripts
cat > "$WORKSPACE_DIR/package.json" << 'EOF'
{
  "name": "demo-app",
  "version": "1.0.0",
  "description": "Demo project for workflow automation",
  "main": "server.js",
  "scripts": {
    "test": "echo '✓ Running tests...' && node test/sample.test.js",
    "dev": "echo '✓ Starting dev server on port 3000...' && node server.js",
    "install": "echo '✓ Installing dependencies...'"
  },
  "dependencies": {
    "express": "^4.18.0"
  }
}
EOF

# Create basic Express server
cat > "$WORKSPACE_DIR/server.js" << 'EOF'
// Simple Express server for demo
const express = require('express');
const app = express();
const PORT = process.env.PORT || 3000;

app.get('/', (req, res) => {
  res.send('Hello from dev server!');
});

app.get('/status', (req, res) => {
  res.json({ status: 'running', port: PORT });
});

if (require.main === module) {
  const server = app.listen(PORT, () => {
    console.log(`✓ Dev server running on port ${PORT}`);
  });
  
  // Auto-shutdown after 2 seconds for demo purposes
  setTimeout(() => {
    console.log('Shutting down demo server...');
    server.close();
  }, 2000);
}

module.exports = app;
EOF

# Create test directory and sample test
sudo -u ga mkdir -p "$WORKSPACE_DIR/test"
cat > "$WORKSPACE_DIR/test/sample.test.js" << 'EOF'
// Simple test file
console.log('Running sample tests...');
console.log('✓ Test 1: Basic functionality - PASSED');
console.log('✓ Test 2: Server starts correctly - PASSED');
console.log('✓ Test 3: Routes respond - PASSED');
console.log('\n✓ All 3 tests passed!');
EOF

# Create workflow instructions
cat > "$WORKSPACE_DIR/WORKFLOW.md" << 'EOF'
# Automate Your Repetitive Workflow

## The Problem
You find yourself typing these commands repeatedly throughout the day:
