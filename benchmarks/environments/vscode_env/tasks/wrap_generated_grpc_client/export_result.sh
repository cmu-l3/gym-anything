#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Wrap Generated gRPC Client Result ==="

WORKSPACE_DIR="/home/ga/workspace/grpc_wrapper_task"

# Focus VSCode and save all files
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+shift+s  # Save all
    sleep 1
    safe_xdotool ga :1 key --delay 200 ctrl+s  # Save current
} || {
    echo "⚠️ Failed to trigger save; continuing"
}

sleep 2

# Wait for key files
wait_for_file "$WORKSPACE_DIR/client_example.py" 3

# Export all relevant files to /tmp for verification
echo "Exporting files for verification..."

# Copy wrapper file if it exists
if [ -f "$WORKSPACE_DIR/src/user_service_client.py" ]; then
    cp "$WORKSPACE_DIR/src/user_service_client.py" /tmp/user_service_client.py
    echo "✅ Wrapper file found and exported"
else
    echo "" > /tmp/user_service_client.py
    echo "⚠️ Wrapper file not found"
fi

# Copy updated example
if [ -f "$WORKSPACE_DIR/client_example.py" ]; then
    cp "$WORKSPACE_DIR/client_example.py" /tmp/client_example.py
    echo "✅ Example file exported"
else
    echo "" > /tmp/client_example.py
    echo "⚠️ Example file not found"
fi

# Check if generated files were modified (they shouldn't be)
if [ -f "$WORKSPACE_DIR/generated/user_service_pb2_grpc.py" ]; then
    md5sum "$WORKSPACE_DIR/generated/user_service_pb2_grpc.py" > /tmp/grpc_final_checksum.txt
else
    echo "0" > /tmp/grpc_final_checksum.txt
fi

# Export directory listing for debugging
ls -la "$WORKSPACE_DIR/src/" > /tmp/src_directory.txt 2>&1 || echo "src/ not found" > /tmp/src_directory.txt

echo "✅ Export complete"
echo "Workspace: $WORKSPACE_DIR"