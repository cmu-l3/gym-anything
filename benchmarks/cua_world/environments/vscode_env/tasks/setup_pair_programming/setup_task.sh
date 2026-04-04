#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Pair Programming Task ==="

WORKSPACE_DIR="/home/ga/workspace/pair_session"
USER_SETTINGS="/home/ga/.config/Code/User/settings.json"

# Create workspace directory
sudo -u ga mkdir -p "$WORKSPACE_DIR"

echo "Creating sample project files..."

# Create a simple project with a bug to debug (context for pair session)
cat > "$WORKSPACE_DIR/app.js" << 'EOF'
function calculateTotal(items) {
    let total = 0;
    for (let i = 0; i <= items.length; i++) {  // BUG: off-by-one error
        total += items[i].price;
    }
    return total;
}

const cart = [
    { name: "Book", price: 15.99 },
    { name: "Pen", price: 2.50 },
    { name: "Notebook", price: 8.75 }
];

console.log("Total:", calculateTotal(cart));
EOF

cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Pair Programming Session

## Bug to Fix
The `calculateTotal` function has an off-by-one error causing it to crash.

## Session Goals
- Fix the array iteration bug together
- Review proper array iteration patterns
- Discuss testing strategies for edge cases
EOF

# Create package.json for proper Node project
cat > "$WORKSPACE_DIR/package.json" << 'EOF'
{
  "name": "pair-session-debug",
  "version": "1.0.0",
  "description": "Collaborative debugging session",
  "main": "app.js",
  "scripts": {
    "start": "node app.js"
  }
}
EOF

# Reset VSCode settings to defaults (simulate user's normal small font setup)
echo "Resetting VSCode settings to default (small font)..."
cat > "$USER_SETTINGS" << 'EOF'
{
  "telemetry.telemetryLevel": "off",
  "update.mode": "none",
  "extensions.autoUpdate": false,
  "editor.fontSize": 12,
  "editor.renderWhitespace": "none",
  "editor.minimap.enabled": true,
  "editor.lineNumbers": "on",
  "editor.tabSize": 4,
  "workbench.colorTheme": "Default Dark+",
  "workbench.startupEditor": "none",
  "files.autoSave": "afterDelay",
  "files.autoSaveDelay": 1000
}
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"
sudo chown -R ga:ga /home/ga/.config/Code/

echo "Opening VSCode with workspace..."
# Open VSCode with the workspace
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Pair Programming Task Setup Complete ==="
echo ""
echo "📝 SCENARIO:"
echo "  You're about to pair program with a junior developer remotely."
echo "  They'll join your screen share in 5 minutes for a debugging session."
echo ""
echo "📋 YOUR TASKS:"
echo "  1. The workspace is already open at $WORKSPACE_DIR"
echo "  2. Open Settings (Ctrl+, or File → Preferences → Settings)"
echo "  3. Increase 'editor.fontSize' to 18 or larger (for screen readability)"
echo "  4. Enable 'editor.renderWhitespace' (set to 'all', 'boundary', 'selection', or 'trailing')"
echo "  5. Ensure 'editor.lineNumbers' is visible (should be 'on', 'relative', or 'interval')"
echo "  6. Create a file 'session_notes.txt' in the workspace with:"
echo "     - Your name as session lead"
echo "     - Today's date"
echo "     - What settings you changed"
echo "     - A note that workspace is ready for collaborative debugging"
echo ""
echo "💡 TIP: Settings are saved in /home/ga/.config/Code/User/settings.json"
echo "        You can edit via Settings UI or directly edit the JSON file"