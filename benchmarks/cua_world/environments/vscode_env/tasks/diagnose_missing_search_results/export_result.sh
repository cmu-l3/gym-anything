#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Diagnose Missing Search Results Task Result ==="

WORKSPACE_DIR="/home/ga/workspace/payment-service"
RESULTS_DIR="/tmp/task_results"

# Ensure VSCode has saved any open files
focus_vscode_window || true
{
  safe_xdotool ga :1 key --delay 200 ctrl+s
  sleep 1
} 2>/dev/null || true

# Create results directory
mkdir -p "$RESULTS_DIR"

# Copy workspace settings (the main artifact)
if [ -f "$WORKSPACE_DIR/.vscode/settings.json" ]; then
  cp "$WORKSPACE_DIR/.vscode/settings.json" "$RESULTS_DIR/workspace_settings.json"
  echo "✅ Copied workspace settings"
else
  echo "⚠️  Workspace settings not found"
  echo "{}" > "$RESULTS_DIR/workspace_settings.json"
fi

# Copy user settings as fallback (in case they modified global settings)
if [ -f "/home/ga/.config/Code/User/settings.json" ]; then
  cp "/home/ga/.config/Code/User/settings.json" "$RESULTS_DIR/user_settings.json"
  echo "✅ Copied user settings"
fi

# Verify the problematic file still exists
if [ -f "$WORKSPACE_DIR/config/payment-providers.json" ]; then
  echo "✅ Target file exists: config/payment-providers.json"
  # Check if it contains the search term
  if grep -q "LEGACY_STRIPE_KEY" "$WORKSPACE_DIR/config/payment-providers.json"; then
    echo "✅ File contains search term"
  fi
fi

# Create a simple test: simulate what VSCode search would find
# (This helps with verification)
cd "$WORKSPACE_DIR"
echo "Simulating search results..."
{
  # Search all files including JSON
  grep -r "LEGACY_STRIPE_KEY" --include="*.json" --include="*.js" --exclude-dir=node_modules . 2>/dev/null | \
    grep -c "config/payment-providers.json" > "$RESULTS_DIR/found_in_config.txt" || echo "0" > "$RESULTS_DIR/found_in_config.txt"
} || echo "0" > "$RESULTS_DIR/found_in_config.txt"

echo "✅ Export complete"
echo "Results saved to: $RESULTS_DIR"
ls -la "$RESULTS_DIR/"