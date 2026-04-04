#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting IntelliJ Keymap Configuration Result ==="

USER_HOME="/home/ga"
VSCODE_USER_DIR="$USER_HOME/.config/Code/User"
EXPORT_DIR="/tmp/keymap_export"

# Create export directory
mkdir -p "$EXPORT_DIR"

# Give VSCode time to save any changes
sleep 2

# Export keybindings.json
echo "Exporting keybindings configuration..."
if [ -f "$VSCODE_USER_DIR/keybindings.json" ]; then
    cp "$VSCODE_USER_DIR/keybindings.json" "$EXPORT_DIR/keybindings.json"
    echo "✅ Keybindings exported"
else
    echo "[]" > "$EXPORT_DIR/keybindings.json"
    echo "⚠️ Keybindings file not found, created empty"
fi

# Export settings.json (in case extension modified it)
echo "Exporting settings configuration..."
if [ -f "$VSCODE_USER_DIR/settings.json" ]; then
    cp "$VSCODE_USER_DIR/settings.json" "$EXPORT_DIR/settings.json"
    echo "✅ Settings exported"
else
    echo "{}" > "$EXPORT_DIR/settings.json"
    echo "⚠️ Settings file not found, created empty"
fi

# Export list of installed extensions
echo "Exporting extensions list..."
su - ga -c "DISPLAY=:1 code --list-extensions" > "$EXPORT_DIR/extensions.txt" 2>&1 || echo "" > "$EXPORT_DIR/extensions.txt"

# Also export extensions directory listing for backup verification
ls -la "$USER_HOME/.vscode/extensions/" > "$EXPORT_DIR/extensions_dir.txt" 2>&1 || echo "No extensions directory" > "$EXPORT_DIR/extensions_dir.txt"

# Create summary report
cat > "$EXPORT_DIR/summary.txt" << EOF
IntelliJ Keymap Configuration Export
Generated: $(date)

Files exported:
- keybindings.json (VSCode keybindings configuration)
- settings.json (VSCode user settings)
- extensions.txt (Installed extensions list)
- extensions_dir.txt (Extensions directory listing)

Keybindings file location: $VSCODE_USER_DIR/keybindings.json
Extensions directory: $USER_HOME/.vscode/extensions/
EOF

echo "✅ Export complete"
echo "Export directory: $EXPORT_DIR"
echo ""
echo "Exported files:"
ls -lh "$EXPORT_DIR/"
echo ""
echo "Keybindings preview:"
head -20 "$EXPORT_DIR/keybindings.json" 2>/dev/null || echo "(empty or not found)"
echo ""
echo "Installed extensions:"
cat "$EXPORT_DIR/extensions.txt"