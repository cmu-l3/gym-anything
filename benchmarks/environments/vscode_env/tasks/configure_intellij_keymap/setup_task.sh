#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up IntelliJ Keymap Configuration Task ==="

WORKSPACE_DIR="/home/ga/workspace/keymap_test"
USER_HOME="/home/ga"
VSCODE_USER_DIR="$USER_HOME/.config/Code/User"

# Create workspace with test files for validating shortcuts
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create sample Python files for testing navigation shortcuts
cat > "$WORKSPACE_DIR/main.py" << 'EOF'
"""Main module for testing navigation shortcuts"""

from utils import helper_function

def hello_world():
    """Simple hello world function"""
    return "Hello, World!"

def another_function():
    """Another function that calls hello_world"""
    result = helper_function()
    message = hello_world()
    return f"{result} - {message}"

class UserService:
    """User service class"""
    
    def get_user(self, user_id):
        """Get user by ID"""
        return {"id": user_id, "name": "John"}

if __name__ == "__main__":
    print(hello_world())
EOF

cat > "$WORKSPACE_DIR/utils.py" << 'EOF'
"""Utility module"""

def helper_function():
    """Helper function"""
    return "Helper called"

def utility_function():
    """Another utility"""
    pass
EOF

cat > "$WORKSPACE_DIR/service.py" << 'EOF'
"""Service implementation"""

class BaseService:
    """Base service interface"""
    def execute(self):
        raise NotImplementedError

class ConcreteService(BaseService):
    """Concrete service implementation"""
    def execute(self):
        return "Service executed"
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Reset keybindings.json to default empty state
echo "Resetting keybindings to default..."
sudo -u ga mkdir -p "$VSCODE_USER_DIR"
echo "[]" | sudo -u ga tee "$VSCODE_USER_DIR/keybindings.json" > /dev/null

# Uninstall any existing IntelliJ keymap extensions to ensure clean state
echo "Removing any existing IntelliJ keymap extensions..."
su - ga -c "DISPLAY=:1 code --uninstall-extension k--kato.intellij-idea-keybindings 2>/dev/null" || true
su - ga -c "DISPLAY=:1 code --uninstall-extension kasecato.vscode-intellij-idea-keybindings 2>/dev/null" || true
sleep 2

# Open VSCode with workspace
echo "Opening VSCode with test workspace..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR' --new-window" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== IntelliJ Keymap Configuration Task Setup Complete ==="
echo "📝 Instructions:"
echo ""
echo "GOAL: Configure IntelliJ IDEA keyboard shortcuts in VSCode"
echo ""
echo "APPROACH 1 (Easier) - Install Extension:"
echo "  1. Press Ctrl+Shift+X to open Extensions"
echo "  2. Search for 'IntelliJ IDEA Keybindings'"
echo "  3. Install extension (by K--Kato or similar)"
echo "  4. Wait for installation to complete"
echo ""
echo "APPROACH 2 (Manual) - Edit keybindings.json:"
echo "  1. Press Ctrl+Shift+P for Command Palette"
echo "  2. Type: Preferences: Open Keyboard Shortcuts (JSON)"
echo "  3. Add keybindings for IntelliJ shortcuts"
echo "  4. Save file (Ctrl+S)"
echo ""
echo "Required shortcuts to configure:"
echo "  • Ctrl+B → Go to Definition"
echo "  • Ctrl+Alt+B → Go to Implementation"
echo "  • Ctrl+N → Go to Symbol in Workspace"
echo "  • Ctrl+Shift+N → Quick Open File"
echo "  • Ctrl+E → Recent Files"
echo ""
echo "Workspace: $WORKSPACE_DIR"
echo "Keybindings file: $VSCODE_USER_DIR/keybindings.json"