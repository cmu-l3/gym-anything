#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up JSON Validation Task ==="

WORKSPACE_DIR="/home/ga/workspace/json_validation_task"
TASK_ASSETS="/workspace/tasks/validate_json_config/assets"

# Create workspace directory
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create corrupted JSON files with various error types

# File 1: config.json - Missing comma, wrong type, trailing comma, logical error
cat > "$WORKSPACE_DIR/config.json" << 'EOF'
{
  "appName": "DataProcessor",
  "version": "2.1.0"
  "port": 8080,
  "debug": true,
  "timeout": "30seconds",
  "maxConnections": -5,
  "retryAttempts": 3
}
EOF

# File 2: database.json - Unquoted key, wrong type, missing closing brace
cat > "$WORKSPACE_DIR/database.json" << 'EOF'
{
  host: "localhost",
  "port": 5432,
  "database": "production_db",
  "username": "admin",
  "password": "secret123",
  "ssl": "true",
  "poolSize": 10
EOF

# File 3: api_settings.json - Mismatched bracket, duplicate key
cat > "$WORKSPACE_DIR/api_settings.json" << 'EOF'
{
  "endpoints": {
    "user": "/api/v1/users",
    "auth": "/api/v1/auth",
    "data": "/api/v1/data"
  ],
  "rateLimit": {
    "enabled": true,
    "maxRequests": 100,
    "windowMs": 60000
  },
  "rateLimit": {
    "enabled": false,
    "maxRequests": 50
  }
}
EOF

# Create a README to provide context
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Configuration Files

These are configuration files received from a third-party integration.
The application crashes when trying to load these files.

Please examine the JSON files and document all validation errors you find.

## Files to check:
- config.json - Application configuration
- database.json - Database connection settings
- api_settings.json - API endpoint and rate limiting configuration

## Task:
Create a validation report (validation_report.md) documenting all JSON errors.
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Open VSCode with workspace and all JSON files
echo "Opening VSCode with JSON files..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 2

focus_vscode_window
sleep 1

# Open each JSON file so errors are visible
echo "Opening JSON files to trigger validation..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR/config.json'" 2>/dev/null || true
sleep 1
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR/database.json'" 2>/dev/null || true
sleep 1
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR/api_settings.json'" 2>/dev/null || true
sleep 1

# Open the README for context
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR/README.md'" 2>/dev/null || true
sleep 1

echo "=== JSON Validation Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. VSCode should show JSON validation errors (red squiggles)"
echo "  2. Open Problems panel with Ctrl+Shift+M"
echo "  3. Click on each error to see details"
echo "  4. Create validation_report.md documenting all errors"
echo "  5. Include file names, line numbers, and clear descriptions"
echo "  6. Save the report (Ctrl+S)"
echo ""
echo "Files to examine:"
echo "  - config.json"
echo "  - database.json"
echo "  - api_settings.json"