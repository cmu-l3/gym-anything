#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Migrate IntelliJ Keymap Task ==="

# Ensure keybindings directory exists
KEYBINDINGS_DIR="/home/ga/.config/Code/User"
sudo -u ga mkdir -p "$KEYBINDINGS_DIR"

# Backup existing keybindings if they exist
KEYBINDINGS_FILE="$KEYBINDINGS_DIR/keybindings.json"
if [ -f "$KEYBINDINGS_FILE" ]; then
    echo "Backing up existing keybindings..."
    sudo -u ga cp "$KEYBINDINGS_FILE" "$KEYBINDINGS_FILE.backup_$(date +%s)"
fi

# Initialize with empty array if doesn't exist or create fresh
echo "[]" | sudo -u ga tee "$KEYBINDINGS_FILE" > /dev/null
sudo chown ga:ga "$KEYBINDINGS_FILE"

# Create a sample workspace for testing shortcuts
WORKSPACE_DIR="/home/ga/workspace/keymap_test"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create sample Java file for testing shortcuts
cat > "$WORKSPACE_DIR/Sample.java" << 'EOF'
public class Sample {
    public static void main(String[] args) {
        System.out.println("Testing IntelliJ keybindings");
        int result = calculateSum(5, 10);
        System.out.println("Result: " + result);
    }
    
    public static int calculateSum(int a, int b) {
        return a + b;
    }
}
EOF

# Create sample Python file for testing
cat > "$WORKSPACE_DIR/sample.py" << 'EOF'
import sys
import os

def calculate_factorial(n):
    if n <= 1:
        return 1
    return n * calculate_factorial(n - 1)

def main():
    result = calculate_factorial(5)
    print(f"Factorial: {result}")

if __name__ == "__main__":
    main()
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Open VSCode with the workspace
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR' '$WORKSPACE_DIR/sample.py'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Migrate IntelliJ Keymap Task Setup Complete ==="
echo "📝 Instructions:"
echo "  Configure these 5 IntelliJ-style keybindings in VSCode:"
echo "  1. Ctrl+Alt+L → editor.action.formatDocument"
echo "  2. Ctrl+B → editor.action.revealDefinition"
echo "  3. Alt+F7 → references-view.findReferences"
echo "  4. Ctrl+Alt+O → editor.action.organizeImports"
echo "  5. Ctrl+Alt+M → editor.action.refactor"
echo ""
echo "  Method A: Use Ctrl+K Ctrl+S to open Keyboard Shortcuts UI"
echo "  Method B: Use Command Palette -> 'Preferences: Open Keyboard Shortcuts (JSON)'"
echo ""
echo "  Keybindings file: $KEYBINDINGS_FILE"