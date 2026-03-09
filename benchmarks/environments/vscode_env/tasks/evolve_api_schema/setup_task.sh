#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Evolve API Schema Task ==="

WORKSPACE_DIR="/home/ga/workspace/user-api"
sudo -u ga mkdir -p "$WORKSPACE_DIR/app"
sudo -u ga mkdir -p "$WORKSPACE_DIR/tests"

# Copy asset files to workspace
ASSETS_DIR="/workspace/tasks/evolve_api_schema/assets"

echo "Copying project files..."
sudo -u ga cp "$ASSETS_DIR/requirements.txt" "$WORKSPACE_DIR/"
sudo -u ga cp "$ASSETS_DIR/README.md" "$WORKSPACE_DIR/"

sudo -u ga cp "$ASSETS_DIR/app/__init__.py" "$WORKSPACE_DIR/app/"
sudo -u ga cp "$ASSETS_DIR/app/main.py" "$WORKSPACE_DIR/app/"
sudo -u ga cp "$ASSETS_DIR/app/models.py" "$WORKSPACE_DIR/app/"
sudo -u ga cp "$ASSETS_DIR/app/schemas.py" "$WORKSPACE_DIR/app/"

sudo -u ga cp "$ASSETS_DIR/tests/__init__.py" "$WORKSPACE_DIR/tests/"
sudo -u ga cp "$ASSETS_DIR/tests/test_user_api.py" "$WORKSPACE_DIR/tests/"

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Install Python dependencies in workspace virtual environment
echo "Installing dependencies..."
cd "$WORKSPACE_DIR"
sudo -u ga python3 -m venv venv || true
sudo -u ga bash -c "source venv/bin/activate && pip install -q -r requirements.txt" || {
    echo "⚠️ Warning: Failed to install some dependencies, continuing..."
}

# Verify pytest is available
if ! sudo -u ga bash -c "source $WORKSPACE_DIR/venv/bin/activate && which pytest" > /dev/null 2>&1; then
    echo "Installing pytest..."
    sudo -u ga bash -c "source $WORKSPACE_DIR/venv/bin/activate && pip install -q pytest fastapi httpx" || true
fi

# Open VSCode with the workspace and key files
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR' '$WORKSPACE_DIR/app/models.py' '$WORKSPACE_DIR/app/schemas.py' '$WORKSPACE_DIR/app/main.py' '$WORKSPACE_DIR/tests/test_user_api.py'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Evolve API Schema Task Setup Complete ==="
echo "📝 Task: Add 'email_verified' boolean field with backward compatibility"
echo ""
echo "Files to edit:"
echo "  • app/models.py - Add field to User class"
echo "  • app/schemas.py - Add field to UserResponse schema"
echo "  • app/main.py - Update mock users"
echo "  • tests/test_user_api.py - Add new test"
echo ""
echo "Requirements:"
echo "  1. Field must have default value: email_verified: bool = False"
echo "  2. Existing tests must still pass (backward compatibility)"
echo "  3. New test must verify field is present and boolean"
echo ""
echo "Press Ctrl+\` to open terminal if needed to run tests"