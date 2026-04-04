#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Code Spell Checker Result ==="

WORKSPACE_DIR="/home/ga/workspace/auth-sync-lib"
RESULTS_DIR="/tmp/spell_checker_results"

# Create results directory
mkdir -p "$RESULTS_DIR"

# Try to save any open files in VSCode
focus_vscode_window || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+shift+s || true
sleep 2

# Wait for files to be saved
wait_for_file "$WORKSPACE_DIR/README.md" 3 || true
wait_for_file "$WORKSPACE_DIR/auth_provider.py" 3 || true

# Copy workspace settings if they exist
if [ -f "$WORKSPACE_DIR/.vscode/settings.json" ]; then
    echo "Copying workspace settings..."
    cp "$WORKSPACE_DIR/.vscode/settings.json" "$RESULTS_DIR/settings.json"
else
    echo "⚠️ Warning: No workspace settings found"
    echo "{}" > "$RESULTS_DIR/settings.json"
fi

# Copy modified files
echo "Copying workspace files..."
cp "$WORKSPACE_DIR/README.md" "$RESULTS_DIR/README.md" 2>/dev/null || echo "README not modified" > "$RESULTS_DIR/README.md"
cp "$WORKSPACE_DIR/auth_provider.py" "$RESULTS_DIR/auth_provider.py" 2>/dev/null || echo "# Not modified" > "$RESULTS_DIR/auth_provider.py"

# List installed extensions
echo "Exporting extensions list..."
su - ga -c "DISPLAY=:1 code --list-extensions" > "$RESULTS_DIR/extensions.txt" 2>&1 || echo "" > "$RESULTS_DIR/extensions.txt"

# Also check extensions directory
ls -la /home/ga/.vscode/extensions/ 2>/dev/null | grep -i "spell" > "$RESULTS_DIR/extensions_dir.txt" || echo "" > "$RESULTS_DIR/extensions_dir.txt"

echo "✅ Results exported to $RESULTS_DIR"
echo "Files exported:"
ls -lh "$RESULTS_DIR/"