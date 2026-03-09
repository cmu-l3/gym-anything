#!/bin/bash
# set -euo pipefail

echo "=== Setting up VSCode configuration ==="

setup_user_vscode() {
    local username=$1
    local home_dir=$2
    
    echo "Setting up VSCode for user: $username"
    
    # Create VSCode config directories
    sudo -u $username mkdir -p "$home_dir/.config/Code/User"
    sudo -u $username mkdir -p "$home_dir/.vscode/extensions"
    sudo -u $username mkdir -p "$home_dir/workspace"
    sudo -u $username mkdir -p "$home_dir/Desktop"
    
    # Copy custom settings if available
    if [ -f "/workspace/config/settings.json" ]; then
        sudo -u $username cp "/workspace/config/settings.json" "$home_dir/.config/Code/User/"
        echo "  - Copied custom settings"
    else
        # Create default settings
        cat > "$home_dir/.config/Code/User/settings.json" << 'SETTINGSEOF'
{
  "telemetry.telemetryLevel": "off",
  "update.mode": "none",
  "extensions.autoUpdate": false,
  "files.autoSave": "afterDelay",
  "files.autoSaveDelay": 1000,
  "editor.fontSize": 14,
  "editor.tabSize": 4,
  "editor.insertSpaces": true,
  "editor.wordWrap": "on",
  "editor.minimap.enabled": true,
  "editor.suggestSelection": "first",
  "editor.acceptSuggestionOnEnter": "on",
  "workbench.startupEditor": "none",
  "workbench.colorTheme": "Default Dark+",
  "terminal.integrated.fontSize": 13,
  "terminal.integrated.shell.linux": "/bin/bash",
  "git.autofetch": true,
  "git.confirmSync": false,
  "git.enableSmartCommit": true,
  "python.linting.enabled": true,
  "python.linting.pylintEnabled": true,
  "python.formatting.provider": "black",
  "javascript.updateImportsOnFileMove.enabled": "always",
  "typescript.updateImportsOnFileMove.enabled": "always",
  "[python]": {
    "editor.defaultFormatter": "ms-python.black-formatter"
  },
  "[javascript]": {
    "editor.defaultFormatter": "esbenp.prettier-vscode"
  },
  "[json]": {
    "editor.defaultFormatter": "esbenp.prettier-vscode"
  }
}
SETTINGSEOF
        chown $username:$username "$home_dir/.config/Code/User/settings.json"
        echo "  - Created default settings"
    fi
    
    # Copy custom keybindings if available
    if [ -f "/workspace/config/keybindings.json" ]; then
        sudo -u $username cp "/workspace/config/keybindings.json" "$home_dir/.config/Code/User/"
        echo "  - Copied custom keybindings"
    else
        # Create default keybindings (empty, use VSCode defaults)
        echo "[]" > "$home_dir/.config/Code/User/keybindings.json"
        chown $username:$username "$home_dir/.config/Code/User/keybindings.json"
        echo "  - Created default keybindings"
    fi
    
    # Install essential extensions
    echo "  - Installing essential extensions..."
    sudo -u $username code --install-extension ms-python.python --force 2>/dev/null || true
    sudo -u $username code --install-extension ms-python.vscode-pylance --force 2>/dev/null || true
    sudo -u $username code --install-extension ms-python.black-formatter --force 2>/dev/null || true
    sudo -u $username code --install-extension dbaeumer.vscode-eslint --force 2>/dev/null || true
    sudo -u $username code --install-extension esbenp.prettier-vscode --force 2>/dev/null || true
    sudo -u $username code --install-extension eamodio.gitlens --force 2>/dev/null || true
    
    # Configure Git
    sudo -u $username git config --global user.name "$username"
    sudo -u $username git config --global user.email "$username@localhost"
    sudo -u $username git config --global init.defaultBranch main
    
    # Create desktop shortcut
    cat > "$home_dir/Desktop/VSCode.desktop" << DESKTOPEOF
[Desktop Entry]
Name=Visual Studio Code
Comment=Code Editor
Exec=code --new-window
Icon=code
StartupNotify=true
Terminal=false
Type=Application
Categories=Development;IDE;
MimeType=text/plain;
DESKTOPEOF
    chown $username:$username "$home_dir/Desktop/VSCode.desktop"
    chmod +x "$home_dir/Desktop/VSCode.desktop"
    echo "  - Created desktop shortcut"
    
    # Create launch script
    cat > "$home_dir/launch_vscode.sh" << 'LAUNCHEOF'
#!/bin/bash
export DISPLAY=${DISPLAY:-:1}
xhost +local: 2>/dev/null || true

code --new-window "$@" > /tmp/vscode_$USER.log 2>&1 &
echo "VSCode started"
echo "Log file: /tmp/vscode_$USER.log"
LAUNCHEOF
    chown $username:$username "$home_dir/launch_vscode.sh"
    chmod +x "$home_dir/launch_vscode.sh"
    echo "  - Created launch script"
}

# Setup for ga user
if id "ga" &>/dev/null; then
    setup_user_vscode "ga" "/home/ga"
fi

echo "=== VSCode configuration completed ==="
echo "VSCode is ready! Users can:"
echo "  - Launch from desktop shortcut"
echo "  - Run 'code' from terminal"
echo "  - Run '~/launch_vscode.sh' for GUI launch"
