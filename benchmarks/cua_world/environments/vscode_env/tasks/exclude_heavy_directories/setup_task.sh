#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Exclude Heavy Directories Task ==="

WORKSPACE_DIR="/home/ga/workspace/monorepo_project"

# Create workspace structure
sudo -u ga mkdir -p "$WORKSPACE_DIR"
cd "$WORKSPACE_DIR"

# Initialize git repo (for realism)
sudo -u ga git init
sudo -u ga git config user.email "agent@test.com"
sudo -u ga git config user.name "Test Agent"

echo "Creating heavy directories with many files..."

# Create node_modules with many files
sudo -u ga mkdir -p node_modules/{package1,package2,package3}/{dist,src,node_modules}
for i in {1..100}; do
    sudo -u ga touch "node_modules/package1/file_$i.js"
    sudo -u ga touch "node_modules/package2/file_$i.js"
done

# Create build directory
sudo -u ga mkdir -p build/{js,css,assets}
for i in {1..50}; do
    sudo -u ga touch "build/js/chunk_$i.js"
    sudo -u ga touch "build/css/style_$i.css"
done

# Create Python virtual environment
sudo -u ga mkdir -p .venv/{lib,bin,include}
for i in {1..30}; do
    sudo -u ga touch ".venv/lib/package_$i.py"
done

# Create Go vendor directory
sudo -u ga mkdir -p vendor/github.com/{org1,org2}/{repo1,repo2}
for i in {1..20}; do
    sudo -u ga touch "vendor/github.com/org1/repo1/file_$i.go"
done

# Create logs directory with files
sudo -u ga mkdir -p logs
for i in {1..5}; do
    sudo -u ga dd if=/dev/zero of="logs/app_$i.log" bs=1M count=2 2>/dev/null
done

# Create actual source code (small, manageable)
sudo -u ga mkdir -p src/{components,utils,services}

cat > "$WORKSPACE_DIR/src/index.js" << 'EOF'
// Main application entry point
import { initApp } from './utils/init';
import { UserService } from './services/user';

function main() {
    initApp();
    const userService = new UserService();
    userService.fetchUsers();
}

main();
EOF

cat > "$WORKSPACE_DIR/src/utils/init.js" << 'EOF'
export function initApp() {
    console.log('Application initialized');
}
EOF

cat > "$WORKSPACE_DIR/src/services/user.js" << 'EOF'
export class UserService {
    fetchUsers() {
        console.log('Fetching users...');
    }
}
EOF

# Create package.json
cat > "$WORKSPACE_DIR/package.json" << 'EOF'
{
  "name": "monorepo-project",
  "version": "1.0.0",
  "description": "Large monorepo project",
  "main": "src/index.js",
  "scripts": {
    "build": "webpack",
    "test": "jest"
  }
}
EOF

# Create README with task instructions
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Monorepo Project

This is a large polyglot monorepo with multiple language ecosystems.

## Problem
VSCode is extremely slow when opening this workspace because it's trying to index:
- node_modules/ (thousands of npm dependency files)
- build/ (generated outputs)
- .venv/ (Python virtual environment)
- vendor/ (Go dependencies)
- logs/ (large log files)

## Task
Configure VSCode workspace settings to exclude these directories from:
1. File watching (files.watcherExclude)
2. Search (search.exclude)
3. Explorer view (files.exclude)

Create or modify .vscode/settings.json with appropriate glob patterns.

## Example Pattern