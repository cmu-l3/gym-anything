#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Adapt Generated API Client Task ==="

WORKSPACE_DIR="/home/ga/workspace/api-adaptation"
ASSETS_DIR="/workspace/tasks/adapt_generated_api_client/assets"

# Create workspace structure
sudo -u ga mkdir -p "$WORKSPACE_DIR/src/generated"
sudo -u ga mkdir -p "$WORKSPACE_DIR/src/services"
sudo -u ga mkdir -p "$WORKSPACE_DIR/src/controllers"
sudo -u ga mkdir -p "$WORKSPACE_DIR/src/components"

# Copy TypeScript configuration
sudo -u ga cp "$ASSETS_DIR/package.json" "$WORKSPACE_DIR/"
sudo -u ga cp "$ASSETS_DIR/tsconfig.json" "$WORKSPACE_DIR/"

# Copy generated API client (new structure)
sudo -u ga cp "$ASSETS_DIR/api-client.ts" "$WORKSPACE_DIR/src/generated/"
# Keep original for checksum verification
sudo -u ga cp "$ASSETS_DIR/api-client.ts" "$WORKSPACE_DIR/src/generated/.api-client.ts.original"

# Copy application code with old access patterns
sudo -u ga cp "$ASSETS_DIR/UserService.ts" "$WORKSPACE_DIR/src/services/"
sudo -u ga cp "$ASSETS_DIR/UserController.ts" "$WORKSPACE_DIR/src/controllers/"
sudo -u ga cp "$ASSETS_DIR/UserProfile.tsx" "$WORKSPACE_DIR/src/components/"

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Install npm dependencies
echo "Installing npm dependencies..."
cd "$WORKSPACE_DIR"
sudo -u ga npm install 2>&1 | tee /tmp/npm_install.log

# Try to compile to show errors
echo ""
echo "=== Initial TypeScript Compilation (expecting errors) ==="
sudo -u ga npm run build 2>&1 | tee /tmp/initial_build.log || true
echo ""

# Open VSCode with workspace and key files
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR' \
  '$WORKSPACE_DIR/src/generated/api-client.ts' \
  '$WORKSPACE_DIR/src/services/UserService.ts' \
  '$WORKSPACE_DIR/src/controllers/UserController.ts'" &

wait_for_vscode 25
wait_for_window "Visual Studio Code" 30

# Click center to focus
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 2

focus_vscode_window
sleep 1

# Open Problems panel to show TypeScript errors
echo "Opening Problems panel..."
safe_xdotool ga :1 key --delay 300 ctrl+shift+m || true
sleep 1

echo "=== Adapt Generated API Client Task Setup Complete ==="
echo ""
echo "📝 Task Summary:"
echo "  Breaking change: User type fields 'email' and 'name' moved to nested 'profile' object"
echo "  Files with errors: UserService.ts, UserController.ts, UserProfile.tsx"
echo "  Generated file (DO NOT EDIT): src/generated/api-client.ts"
echo ""
echo "📋 Steps:"
echo "  1. Check Problems panel (Ctrl+Shift+M) for TypeScript errors"
echo "  2. Review new User type structure in api-client.ts"
echo "  3. Update application code: user.email → user.profile.email"
echo "  4. Update application code: user.name → user.profile.name"
echo "  5. Save all files (Ctrl+K S)"
echo "  6. Verify build succeeds: npm run build (in terminal)"