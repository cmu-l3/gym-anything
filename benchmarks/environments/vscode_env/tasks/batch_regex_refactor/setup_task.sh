#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Batch Regex Refactor Task ==="

WORKSPACE_DIR="/home/ga/workspace/legacy-api-project"
TASK_ASSETS="/workspace/tasks/batch_regex_refactor/assets"

# Create workspace structure
sudo -u ga mkdir -p "$WORKSPACE_DIR/src"
sudo -u ga mkdir -p "$WORKSPACE_DIR/tests"

# Create package.json
cat > "$WORKSPACE_DIR/package.json" << 'EOF'
{
  "name": "legacy-api-project",
  "version": "1.0.0",
  "description": "Project with legacy API calls to refactor",
  "main": "src/index.js",
  "scripts": {
    "start": "node src/index.js"
  },
  "dependencies": {
    "api-client": "^2.0.0"
  }
}
EOF

# Create README with instructions
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Legacy API Project

This project needs to migrate from callback-style API calls to Promise-style.

## Old Pattern (Deprecated)