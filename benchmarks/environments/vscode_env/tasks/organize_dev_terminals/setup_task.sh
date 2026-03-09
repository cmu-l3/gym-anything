#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Organize Dev Terminals Task ==="

WORKSPACE_DIR="/home/ga/workspace/dev_project"
sudo -u ga mkdir -p "$WORKSPACE_DIR"/{frontend/src,backend,logs}

# Create frontend package.json
cat > "$WORKSPACE_DIR/frontend/package.json" << 'EOF'
{
  "name": "frontend-app",
  "version": "1.0.0",
  "description": "Frontend application",
  "scripts": {
    "start": "react-scripts start",
    "build": "react-scripts build",
    "test": "react-scripts test"
  },
  "dependencies": {
    "react": "^18.2.0",
    "react-dom": "^18.2.0"
  }
}
EOF

# Create frontend App.js
cat > "$WORKSPACE_DIR/frontend/src/App.js" << 'EOF'
import React from 'react';

function App() {
  return (
    <div className="App">
      <h1>Hello World</h1>
      <p>Welcome to the frontend application</p>
    </div>
  );
}

export default App;
EOF

# Create frontend README
cat > "$WORKSPACE_DIR/frontend/README.md" << 'EOF'
# Frontend Application

Run development server: