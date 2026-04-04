#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Settings Sync Task ==="

# VSCode configuration directories
CONFIG_DIR="/home/ga/.config/Code/User"
STORAGE_DIR="$CONFIG_DIR/globalStorage"
SYNC_DIR="$CONFIG_DIR/sync"

# Ensure config directories exist
sudo -u ga mkdir -p "$CONFIG_DIR"
sudo -u ga mkdir -p "$STORAGE_DIR"

# Create initial settings.json with some custom settings (to make sync valuable)
cat > "$CONFIG_DIR/settings.json" << 'EOF'
{
  "telemetry.telemetryLevel": "off",
  "update.mode": "none",
  "extensions.autoUpdate": false,
  "files.autoSave": "afterDelay",
  "files.autoSaveDelay": 1000,
  "editor.fontSize": 14,
  "editor.tabSize": 4,
  "editor.wordWrap": "on",
  "workbench.colorTheme": "Default Dark+",
  "workbench.startupEditor": "none",
  "git.autofetch": true,
  "git.confirmSync": false
}
EOF

# Create custom keybindings
cat > "$CONFIG_DIR/keybindings.json" << 'EOF'
[
  {
    "key": "ctrl+shift+t",
    "command": "workbench.action.terminal.new"
  }
]
EOF

# Ensure Settings Sync is DISABLED initially
# Remove any existing sync configuration
sudo rm -rf "$SYNC_DIR" 2>/dev/null || true

# Create/modify storage.json to disable sync
cat > "$STORAGE_DIR/storage.json" << 'EOF'
{
  "userDataSync.state": {
    "enabled": false
  }
}
EOF

sudo chown -R ga:ga "$CONFIG_DIR"

# Create a workspace to open
WORKSPACE_DIR="/home/ga/workspace/sync_demo"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Settings Sync Demo

This workspace is for demonstrating Settings Sync configuration.

## Task
Enable Settings Sync to synchronize your VSCode configuration across devices.

## Steps
1. Open Command Palette (Ctrl+Shift+P)
2. Search: "Settings Sync: Turn On"
3. Select sync options (Settings, Keybindings, Extensions, Snippets, UI State)
4. Complete sync setup
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Launch VSCode
echo "Launching VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Settings Sync Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Press Ctrl+Shift+P to open Command Palette"
echo "  2. Type: 'Settings Sync: Turn On'"
echo "  3. In the dialog, ensure these options are selected:"
echo "     - Settings ✓"
echo "     - Keyboard Shortcuts ✓"
echo "     - Extensions ✓"
echo "     - User Snippets ✓"
echo "     - UI State ✓"
echo "  4. Proceed with enabling sync"
echo ""
echo "Current state: Settings Sync is DISABLED"
echo "Custom settings and keybindings are already configured"