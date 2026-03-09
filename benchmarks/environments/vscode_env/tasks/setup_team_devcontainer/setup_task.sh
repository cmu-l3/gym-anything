#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Team Devcontainer Configuration Task ==="

WORKSPACE_DIR="/home/ga/workspace/team-project"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create a basic Node.js project structure
cat > "$WORKSPACE_DIR/package.json" << 'EOF'
{
  "name": "team-project",
  "version": "1.0.0",
  "description": "Team collaboration project",
  "main": "index.js",
  "scripts": {
    "start": "node index.js",
    "test": "echo \"Error: no test specified\" && exit 1"
  },
  "keywords": ["team", "collaboration"],
  "author": "Team",
  "license": "MIT",
  "dependencies": {
    "express": "^4.18.0",
    "lodash": "^4.17.21"
  },
  "devDependencies": {
    "eslint": "^8.0.0",
    "prettier": "^2.8.0"
  }
}
EOF

# Create sample source files
cat > "$WORKSPACE_DIR/index.js" << 'EOF'
const express = require('express');
const app = express();
const port = 3000;

app.get('/', (req, res) => {
  res.send('Hello Team!');
});

app.listen(port, () => {
  console.log(`App listening on port ${port}`);
});
EOF

cat > "$WORKSPACE_DIR/.eslintrc.json" << 'EOF'
{
  "env": {
    "node": true,
    "es2021": true
  },
  "extends": "eslint:recommended",
  "parserOptions": {
    "ecmaVersion": 12
  },
  "rules": {
    "indent": ["error", 2],
    "quotes": ["error", "single"],
    "semi": ["error", "always"]
  }
}
EOF

cat > "$WORKSPACE_DIR/.prettierrc.json" << 'EOF'
{
  "semi": true,
  "singleQuote": true,
  "tabWidth": 2,
  "trailingComma": "es5"
}
EOF

# Create a basic README
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Team Project

This is a collaborative team project. We need consistent development environments!

## Problem

Currently, team members use different setups:
- Different Node.js versions
- Different extensions installed
- Different formatter configurations
- Different operating systems

This causes "works on my machine" issues and wastes time.

## Solution

Set up a devcontainer configuration to provide identical containerized development environments for all team members.

## TODO

Configure development container with:
1. Node.js 18 base image
2. Required extensions (ESLint, Prettier, GitLens)
3. Automatic npm install on container creation
4. Consistent editor settings
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Open VSCode with the workspace
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Team Devcontainer Configuration Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Create .devcontainer/ directory in project root"
echo "  2. Create devcontainer.json with Node.js 18 configuration"
echo "  3. Specify required extensions: ESLint, Prettier, GitLens"
echo "  4. Set postCreateCommand to 'npm install'"
echo "  5. Configure editor settings (format on save, Prettier formatter)"
echo "  6. Create README_DEVCONTAINER.md with team instructions"
echo ""
echo "Project location: $WORKSPACE_DIR"