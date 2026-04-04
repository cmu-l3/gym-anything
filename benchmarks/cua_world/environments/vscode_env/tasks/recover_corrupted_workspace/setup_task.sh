#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Workspace Recovery Task ==="

WORKSPACE_DIR="/home/ga/workspace/recovery_task"
sudo -u ga mkdir -p "$WORKSPACE_DIR"
sudo -u ga mkdir -p "$WORKSPACE_DIR/.vscode"

# Create a sample Python project
cat > "$WORKSPACE_DIR/main.py" << 'EOF'
import math
import os

def calculate_area(radius):
    """Calculate circle area"""
    return math.pi * radius ** 2

def process_data(items):
    """Process list of items"""
    result = []
    for item in items:
        result.append(item.upper())
    return result

if __name__ == "__main__":
    area = calculate_area(5)
    print(f"Area: {area}")
    
    data = ["hello", "world", "test"]
    processed = process_data(data)
    print(processed)
EOF

cat > "$WORKSPACE_DIR/helper.py" << 'EOF'
def helper_function(x, y):
    """Helper function for calculations"""
    return x + y

class DataProcessor:
    def __init__(self, name):
        self.name = name
    
    def process(self, value):
        return value * 2
EOF

cat > "$WORKSPACE_DIR/requirements.txt" << 'EOF'
requests==2.28.0
numpy==1.24.0
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Ensure Python extension is installed
echo "Ensuring Python extension is installed..."
su - ga -c "DISPLAY=:1 code --install-extension ms-python.python --force" 2>&1 || true
sleep 2

# Create workspace settings (will be corrupted)
cat > "$WORKSPACE_DIR/.vscode/settings.json" << 'EOF'
{
  "python.linting.enabled": true,
  "python.linting.pylintEnabled": true,
  "editor.formatOnSave": true,
  "editor.tabSize": 4,
  "files.autoSave": "afterDelay"
}
EOF

# Backup valid settings for verification purposes
sudo -u ga cp "$WORKSPACE_DIR/.vscode/settings.json" "/tmp/valid_workspace_settings.json"

# Now introduce corruption to workspace settings
cat > "$WORKSPACE_DIR/.vscode/settings.json" << 'EOF'
{
  "python.linting.enabled": true,
  "python.linting.pylintEnabled": true,
  "editor.formatOnSave": true,
  "editor.tabSize": 4,
  "files.autoSave": "afterDelay",
  "corrupted.setting": "this value is missing a closing quote
}
EOF

# Also corrupt user settings
SETTINGS_DIR="/home/ga/.config/Code/User"
sudo -u ga mkdir -p "$SETTINGS_DIR"

# Backup current settings
if [ -f "$SETTINGS_DIR/settings.json" ]; then
    sudo -u ga cp "$SETTINGS_DIR/settings.json" "$SETTINGS_DIR/settings.json.backup"
fi

# Introduce corruption in user settings as well
cat > "$SETTINGS_DIR/settings.json" << 'EOF'
{
  "telemetry.telemetryLevel": "off",
  "update.mode": "none",
  "editor.fontSize": 14,
  "editor.tabSize": 4,
  "workbench.colorTheme": "Default Dark+",
  "files.autoSave": "afterDelay",
  "broken.key": "missing quote at end
}
EOF

sudo chown -R ga:ga "$SETTINGS_DIR"

# Create a marker file to track that corruption was set up
echo "Corruption introduced at $(date)" > /tmp/corruption_marker.txt
echo "Settings corrupted: missing quote in both user and workspace settings.json" >> /tmp/corruption_marker.txt
echo "Expected fix: Remove or fix the 'corrupted.setting' and 'broken.key' lines" >> /tmp/corruption_marker.txt

sudo chown ga:ga /tmp/corruption_marker.txt

# Open VSCode with the corrupted workspace
echo "Opening VSCode with corrupted workspace..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR' '$WORKSPACE_DIR/main.py'" &
wait_for_vscode 25
wait_for_window "Visual Studio Code" 35

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 2

focus_vscode_window
sleep 3

# Try to trigger extension loading and make issues more visible
# Open Output panel to show logs
su - ga -c "DISPLAY=:1 xdotool key ctrl+shift+u" 2>&1 || true
sleep 1

echo "=== Workspace Recovery Task Setup Complete ==="
echo "⚠️  CORRUPTION INTRODUCED:"
echo "  - settings.json has JSON syntax error (missing quote)"
echo "  - Extensions may fail to load properly"
echo "  - IntelliSense may not work"
echo ""
echo "📝 Agent Instructions:"
echo "  1. Check Developer logs and Output panel for errors"
echo "  2. Fix settings.json syntax errors (user and/or workspace)"
echo "  3. Diagnose extension issues (disable/re-enable if needed)"
echo "  4. Verify IntelliSense works in Python files"
echo "  5. Create RECOVERY_LOG.md documenting the fix"
echo ""
echo "Workspace: $WORKSPACE_DIR"