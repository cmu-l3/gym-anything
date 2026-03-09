#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Diagnose Library Behavior Result ==="

WORKSPACE_DIR="/home/ga/workspace/data_pipeline"
CONFIG_FILE="$WORKSPACE_DIR/.datamorph.config"

# Focus VSCode and save
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+s
} || {
    echo "⚠️ Failed to save; continuing"
}

sleep 1

# Export config file if it exists
if [ -f "$CONFIG_FILE" ]; then
    echo "Config file found, copying to /tmp..."
    cp "$CONFIG_FILE" /tmp/datamorph_config.json 2>/dev/null || echo "{}" > /tmp/datamorph_config.json
else
    echo "Config file not found at $CONFIG_FILE"
    echo "{}" > /tmp/datamorph_config.json
fi

# Try to run the script and capture output
echo "Running process.py to test configuration..."
cd "$WORKSPACE_DIR"
sudo -u ga timeout 10 python3 process.py > /tmp/datamorph_output.txt 2>&1 || echo "Script execution failed or timed out" > /tmp/datamorph_output.txt

echo "✅ Export complete"
echo "Config file: $CONFIG_FILE"
cat /tmp/datamorph_config.json 2>/dev/null || echo "(no config)"
echo ""
echo "Script output:"
cat /tmp/datamorph_output.txt