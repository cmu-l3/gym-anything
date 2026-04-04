#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Code Spell Checker Task ==="

WORKSPACE_DIR="/home/ga/workspace/auth-sync-lib"
VSCODE_DIR="$WORKSPACE_DIR/.vscode"

# Create workspace directory
sudo -u ga mkdir -p "$WORKSPACE_DIR"
cd "$WORKSPACE_DIR"

# Create README.md with intentional typos
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# AuthSync Library

A Python library for syncronizing authentication tokens with CRM systems.

## Features

- Automaticaly refreshes access tokens
- Integrates with SalesForce and HubSpot
- Provides thread-safe token managment
- Suports custom retry policies

## Installation

Install the libary using pip:
