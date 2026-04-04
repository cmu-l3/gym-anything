#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Dependency Conflict Resolution Task ==="

WORKSPACE_DIR="/home/ga/workspace/conflict_app"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create package.json with conflicting dependencies
cat > "$WORKSPACE_DIR/package.json" << 'EOF'
{
  "name": "conflict-app",
  "version": "1.0.0",
  "description": "Sample app with dependency conflict",
  "main": "app.js",
  "scripts": {
    "start": "node app.js"
  },
  "dependencies": {
    "react": "^17.0.2",
    "react-dom": "^18.2.0",
    "express": "^4.18.2"
  },
  "devDependencies": {
    "nodemon": "^2.0.20"
  }
}
EOF

# Create a simple app.js that uses the dependencies
cat > "$WORKSPACE_DIR/app.js" << 'EOF'
const express = require('express');
const React = require('react');
const ReactDOM = require('react-dom');

const app = express();
const PORT = 3000;

app.get('/', (req, res) => {
  res.send(`
    <h1>Dependency Conflict Demo App</h1>
    <p>React version: ${React.version}</p>
    <p>If you see this, dependencies are resolved!</p>
  `);
});

console.log('Dependencies loaded successfully!');
console.log('React version:', React.version);

if (require.main === module) {
  app.listen(PORT, () => {
    console.log(`Server running on port ${PORT}`);
  });
}

module.exports = app;
EOF

# Create README for the project
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Conflict App

This project has a dependency conflict that needs to be resolved.

## Issue

The current setup has:
- react@17.0.2
- react-dom@18.2.0

React DOM 18.x requires React 18.x as a peer dependency, causing a conflict.

## Solution

Update react to version ^18.0.0 or higher in package.json.
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Backup original package.json for verification
sudo -u ga cp "$WORKSPACE_DIR/package.json" "$WORKSPACE_DIR/.original_package.json"

# Try to install dependencies to show the error (but don't fail if it errors)
cd "$WORKSPACE_DIR"
echo "Attempting npm install to demonstrate the conflict..."
sudo -u ga npm install --legacy-peer-deps 2>&1 | tee /tmp/initial_npm_error.txt || true

# Open VSCode with the workspace
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR' '$WORKSPACE_DIR/package.json'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

# Open integrated terminal and show the conflict
sleep 2
echo "Opening integrated terminal..."
su - ga -c "DISPLAY=:1 xdotool key ctrl+grave" || true  # Ctrl+` to open terminal
sleep 2

# Clear terminal and run npm install to show error
echo "Running npm install to display conflict error..."
su - ga -c "DISPLAY=:1 xdotool type --delay 100 'cd /home/ga/workspace/conflict_app && npm install'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key Return" || true
sleep 3

echo "=== Dependency Conflict Resolution Task Setup Complete ==="
echo ""
echo "📋 Task Overview:"
echo "  • React-DOM 18.2.0 requires React 18.x"
echo "  • Current React version is 17.0.2"
echo "  • Update package.json to resolve the conflict"
echo ""
echo "📝 Instructions:"
echo "  1. Read the terminal error showing the peer dependency conflict"
echo "  2. Press Ctrl+P and type 'package.json' to open the file"
echo "  3. Find the 'react' entry in dependencies"
echo "  4. Update version from '^17.0.2' to '^18.0.0' or '^18.2.0'"
echo "  5. Save the file (Ctrl+S)"
echo ""
echo "✅ The export script will verify the conflict is resolved"