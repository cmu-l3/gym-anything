#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Compare Git Branches Task ==="

WORKSPACE_DIR="/home/ga/workspace/auth_project"
sudo -u ga mkdir -p "$WORKSPACE_DIR/config"

# Initialize Git repository
cd "$WORKSPACE_DIR"
sudo -u ga git init
sudo -u ga git config user.name "GA User"
sudo -u ga git config user.email "ga@localhost"

# Create main branch with original database config
cat > "$WORKSPACE_DIR/config/database.py" << 'EOF'
# Database Configuration
DATABASE_HOST = "localhost"
DATABASE_PORT = 5432
DATABASE_NAME = "myapp_db"
DATABASE_USER = "admin"
DATABASE_PASSWORD = "password123"  # TODO: Move to env var

def get_connection_string():
    return f"postgresql://{DATABASE_USER}:{DATABASE_PASSWORD}@{DATABASE_HOST}:{DATABASE_PORT}/{DATABASE_NAME}"
EOF

# Create additional files to make it realistic
cat > "$WORKSPACE_DIR/config/__init__.py" << 'EOF'
from .database import get_connection_string

__all__ = ['get_connection_string']
EOF

cat > "$WORKSPACE_DIR/main.py" << 'EOF'
from config import get_connection_string

def main():
    conn_str = get_connection_string()
    print(f"Connecting to: {conn_str}")

if __name__ == "__main__":
    main()
EOF

cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Authentication Project

This project implements user authentication with database integration.

## Setup

1. Install dependencies
2. Configure database settings
3. Run migrations
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Initial commit on main
cd "$WORKSPACE_DIR"
sudo -u ga git add .
sudo -u ga git commit -m "Initial commit with database configuration"

# Create feature-auth branch with security improvements
sudo -u ga git checkout -b feature-auth

cat > "$WORKSPACE_DIR/config/database.py" << 'EOF'
# Database Configuration
import os

DATABASE_HOST = os.getenv("DB_HOST", "localhost")
DATABASE_PORT = int(os.getenv("DB_PORT", "5432"))
DATABASE_NAME = os.getenv("DB_NAME", "myapp_db")
DATABASE_USER = os.getenv("DB_USER", "app_user")  # Changed from admin
DATABASE_PASSWORD = os.getenv("DB_PASSWORD")  # Now required env var

# Connection pooling settings
POOL_SIZE = int(os.getenv("DB_POOL_SIZE", "10"))
MAX_OVERFLOW = int(os.getenv("DB_MAX_OVERFLOW", "20"))

def get_connection_string():
    if not DATABASE_PASSWORD:
        raise ValueError("DATABASE_PASSWORD environment variable must be set")
    return f"postgresql://{DATABASE_USER}:{DATABASE_PASSWORD}@{DATABASE_HOST}:{DATABASE_PORT}/{DATABASE_NAME}"

def get_pool_config():
    return {
        "pool_size": POOL_SIZE,
        "max_overflow": MAX_OVERFLOW
    }
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"

sudo -u ga git add .
sudo -u ga git commit -m "feat: Add environment-based auth and connection pooling"

# Switch back to main branch
sudo -u ga git checkout main

# Verify branches exist
echo "Verifying Git setup..."
sudo -u ga git branch -a
echo "Current branch: $(sudo -u ga git branch --show-current)"

# Open VSCode in the workspace
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Compare Git Branches Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Open Source Control panel (Ctrl+Shift+G)"
echo "  2. Compare branches 'main' and 'feature-auth'"
echo "  3. Open diff for file: config/database.py"
echo ""
echo "Repository: $WORKSPACE_DIR"
echo "Current branch: main"
echo "Feature branch: feature-auth"
echo "Target file: config/database.py"