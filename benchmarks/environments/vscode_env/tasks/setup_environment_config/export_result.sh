#!/bin/bash
# set -euo pipefail

echo "=== Exporting Environment Config Result ==="

PROJECT_DIR="/home/ga/workspace/env_config_project"

# Export .env file if it exists
if [ -f "$PROJECT_DIR/.env" ]; then
    echo "Exporting .env file..."
    cp "$PROJECT_DIR/.env" /tmp/result.env 2>&1 || echo "" > /tmp/result.env
    echo "✅ .env file exported to /tmp/result.env"
else
    echo "⚠️ .env file not found"
    echo "" > /tmp/result.env
fi

# Export file listing for debugging
ls -la "$PROJECT_DIR" > /tmp/project_files.txt 2>&1 || echo "Directory not found" > /tmp/project_files.txt

# Try to capture application startup attempt (for debugging)
cd "$PROJECT_DIR" 2>/dev/null || true
timeout 3 sudo -u ga npm start > /tmp/app_startup.log 2>&1 || true

echo "✅ Export complete"