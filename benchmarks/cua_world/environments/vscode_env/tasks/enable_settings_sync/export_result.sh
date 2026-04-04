#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Settings Sync Configuration ==="

CONFIG_DIR="/home/ga/.config/Code/User"
EXPORT_DIR="/tmp/vscode_sync_export"

# Create export directory
mkdir -p "$EXPORT_DIR"

# Give VSCode time to save any configuration changes
sleep 2

# Export VSCode settings files
echo "Exporting settings.json..."
cp "$CONFIG_DIR/settings.json" "$EXPORT_DIR/settings.json" 2>/dev/null || echo "{}" > "$EXPORT_DIR/settings.json"

echo "Exporting keybindings.json..."
cp "$CONFIG_DIR/keybindings.json" "$EXPORT_DIR/keybindings.json" 2>/dev/null || echo "[]" > "$EXPORT_DIR/keybindings.json"

# Export globalStorage (contains sync state)
echo "Exporting storage.json..."
cp "$CONFIG_DIR/globalStorage/storage.json" "$EXPORT_DIR/storage.json" 2>/dev/null || echo "{}" > "$EXPORT_DIR/storage.json"

# Export sync folder if it exists
if [ -d "$CONFIG_DIR/sync" ]; then
    echo "Exporting sync folder..."
    mkdir -p "$EXPORT_DIR/sync"
    cp -r "$CONFIG_DIR/sync/"* "$EXPORT_DIR/sync/" 2>/dev/null || echo "No sync data"
else
    echo "No sync folder found"
fi

# Get VSCode process info for additional verification
ps aux | grep -i "code" | grep -v grep > "$EXPORT_DIR/vscode_processes.txt" 2>&1 || echo "No VSCode process" > "$EXPORT_DIR/vscode_processes.txt"

# List extensions (might be synced)
su - ga -c "DISPLAY=:1 code --list-extensions" > "$EXPORT_DIR/extensions_list.txt" 2>&1 || echo "" > "$EXPORT_DIR/extensions_list.txt"

# Check if Settings Sync preferences appear in settings
grep -i "sync" "$CONFIG_DIR/settings.json" > "$EXPORT_DIR/sync_settings.txt" 2>/dev/null || echo "No sync settings found" > "$EXPORT_DIR/sync_settings.txt"

echo "✅ Configuration exported to $EXPORT_DIR"
ls -la "$EXPORT_DIR"
echo ""
echo "Storage.json contents:"
cat "$EXPORT_DIR/storage.json" 2>/dev/null || echo "File not found"