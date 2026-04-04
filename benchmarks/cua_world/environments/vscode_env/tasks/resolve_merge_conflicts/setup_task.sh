#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Resolve Merge Conflicts Task ==="

WORKSPACE_DIR="/home/ga/workspace/merge_conflict_project"

# Clean up any existing directory
sudo rm -rf "$WORKSPACE_DIR"
sudo -u ga mkdir -p "$WORKSPACE_DIR/src/utils"

cd "$WORKSPACE_DIR"

# Initialize Git repository
sudo -u ga git init
sudo -u ga git config user.name "GA User"
sudo -u ga git config user.email "ga@localhost"

# Create initial versions of files (common ancestor)
cat > "$WORKSPACE_DIR/src/config.py" << 'EOF'
import os

class DatabaseConfig:
    def __init__(self):
        self.db_url = "postgresql://localhost:5432/testdb"
        self.timeout = 30
        self.max_connections = 10
EOF

cat > "$WORKSPACE_DIR/src/utils/logger.py" << 'EOF'
import logging

def setup_logger(name):
    logger = logging.getLogger(name)
    logger.setLevel(logging.WARNING)
    handler = logging.StreamHandler()
    logger.addHandler(handler)
    return logger
EOF

cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Project Setup

## Prerequisites
- Python 3.10+
- PostgreSQL

## Installation

Instructions coming soon...

## Running the Application
