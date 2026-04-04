#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Adapt Generated API Client Result ==="

WORKSPACE_DIR="/home/ga/workspace/api-adaptation"

# Focus VSCode and save all files
focus_vscode_window
sleep 1

echo "Saving all files..."
safe_xdotool ga :1 key --delay 300 ctrl+k s || {
    echo "⚠️ Ctrl+K S failed, trying Ctrl+S"
    safe_xdotool ga :1 key --delay 300 ctrl+s || true
}

sleep 2

# Wait for files to be written
wait_for_file "$WORKSPACE_DIR/src/services/UserService.ts" 3
wait_for_file "$WORKSPACE_DIR/src/controllers/UserController.ts" 3
wait_for_file "$WORKSPACE_DIR/src/components/UserProfile.tsx" 3

# Run TypeScript compilation and export results
echo "Running TypeScript compilation..."
cd "$WORKSPACE_DIR"
sudo -u ga npm run build > /tmp/final_build_output.log 2>&1
BUILD_EXIT_CODE=$?
echo $BUILD_EXIT_CODE > /tmp/build_exit_code.txt

echo "Build exit code: $BUILD_EXIT_CODE"

# Also try tsc directly
sudo -u ga npx tsc --noEmit > /tmp/tsc_output.log 2>&1
TSC_EXIT_CODE=$?
echo $TSC_EXIT_CODE > /tmp/tsc_exit_code.txt

echo "TSC exit code: $TSC_EXIT_CODE"

# Export file contents for verification
cat "$WORKSPACE_DIR/src/services/UserService.ts" > /tmp/UserService.ts 2>&1 || echo "" > /tmp/UserService.ts
cat "$WORKSPACE_DIR/src/controllers/UserController.ts" > /tmp/UserController.ts 2>&1 || echo "" > /tmp/UserController.ts
cat "$WORKSPACE_DIR/src/components/UserProfile.tsx" > /tmp/UserProfile.tsx 2>&1 || echo "" > /tmp/UserProfile.tsx
cat "$WORKSPACE_DIR/src/generated/api-client.ts" > /tmp/api-client.ts 2>&1 || echo "" > /tmp/api-client.ts

# Calculate checksum of generated file
sha256sum "$WORKSPACE_DIR/src/generated/api-client.ts" 2>/dev/null | awk '{print $1}' > /tmp/api_client_checksum.txt || echo "" > /tmp/api_client_checksum.txt
sha256sum "$WORKSPACE_DIR/src/generated/.api-client.ts.original" 2>/dev/null | awk '{print $1}' > /tmp/api_client_original_checksum.txt || echo "" > /tmp/api_client_original_checksum.txt

echo "✅ Export complete"
echo "Workspace: $WORKSPACE_DIR"