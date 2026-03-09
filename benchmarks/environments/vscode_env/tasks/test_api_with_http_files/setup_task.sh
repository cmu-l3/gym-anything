#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up REST API Testing with HTTP Files Task ==="

WORKSPACE_DIR="/home/ga/workspace/api_test"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Install REST Client extension if not already installed
echo "Checking REST Client extension..."
if ! su - ga -c "DISPLAY=:1 code --list-extensions" | grep -q "humao.rest-client"; then
    echo "Installing REST Client extension..."
    su - ga -c "DISPLAY=:1 code --install-extension humao.rest-client" || true
    sleep 3
else
    echo "REST Client extension already installed"
fi

# Copy mock API server to workspace
MOCK_SERVER_ASSET="/workspace/tasks/test_api_with_http_files/assets/mock-api-server.js"
if [ -f "$MOCK_SERVER_ASSET" ]; then
    sudo -u ga cp "$MOCK_SERVER_ASSET" "$WORKSPACE_DIR/"
    echo "Mock API server copied to workspace"
else
    echo "⚠️ Warning: Mock API server not found at $MOCK_SERVER_ASSET"
fi

# Create instructions file
cat > "$WORKSPACE_DIR/INSTRUCTIONS.md" << 'EOF'
# Task: Create HTTP Request File

## Goal
Create a file named `api-tests.http` to test the REST API running at `http://localhost:3000`.

## Requirements

1. **Variable Definition**: Define `@baseUrl = http://localhost:3000`

2. **GET all users**: 
   - Method: GET
   - Path: /api/users
   - Header: Accept: application/json

3. **POST new user**:
   - Method: POST
   - Path: /api/users
   - Header: Content-Type: application/json
   - Body: JSON with "name" and "email" fields

4. **GET specific user**:
   - Method: GET
   - Path: /api/users/1

5. **Separators**: Use `###` to separate requests

## Example Format
