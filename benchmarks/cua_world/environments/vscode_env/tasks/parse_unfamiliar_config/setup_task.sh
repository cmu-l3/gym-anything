#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Parse Unfamiliar Config Task ==="

WORKSPACE_DIR="/home/ga/workspace/api-gateway-config"
TASK_ASSETS="/workspace/tasks/parse_unfamiliar_config/assets"

# Create workspace directory structure
sudo -u ga mkdir -p "$WORKSPACE_DIR/examples"

# Copy asset files to workspace
echo "Copying configuration files..."
sudo -u ga cp "$TASK_ASSETS/gateway_config.yaml" "$WORKSPACE_DIR/"
sudo -u ga cp "$TASK_ASSETS/gateway_config.schema.json" "$WORKSPACE_DIR/"
sudo -u ga cp "$TASK_ASSETS/README.md" "$WORKSPACE_DIR/"
sudo -u ga cp "$TASK_ASSETS/rate_limit_example.yaml" "$WORKSPACE_DIR/benchmarks/cua_world/environments/"

# Set permissions
sudo chown -R ga:ga "$WORKSPACE_DIR"
sudo chmod -R 755 "$WORKSPACE_DIR"

# Open VSCode with workspace
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

# Open the main config file
sleep 1
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR/gateway_config.yaml'" &
sleep 2

echo "=== Parse Unfamiliar Config Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Open gateway_config.yaml (should already be open)"
echo "  2. Use Ctrl+F to search for 'payment-service' (not the commented one!)"
echo "  3. Find the rate_limit section under payment-service"
echo "  4. Update bkt_sz: 50 -> 200"
echo "  5. Update thr_win: 60 -> 30"
echo "  6. Add line: priority_bypass: true (same indent as other rate_limit fields)"
echo "  7. Save file (Ctrl+S)"
echo ""
echo "💡 Tip: Check benchmarks/cua_world/environments/rate_limit_example.yaml to understand field meanings"