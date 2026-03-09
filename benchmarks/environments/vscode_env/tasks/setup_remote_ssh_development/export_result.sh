#!/bin/bash
# set -euo pipefail

echo "=== Exporting Remote SSH Development Result ==="

# Give time for any running processes to stabilize
sleep 2

# Export SSH config
if [ -f /home/ga/.ssh/config ]; then
    cp /home/ga/.ssh/config /tmp/ssh_config.txt 2>/dev/null || echo "No SSH config" > /tmp/ssh_config.txt
else
    echo "No SSH config found" > /tmp/ssh_config.txt
fi

# Check if VSCode Server is installed on "remote"
if [ -d /home/developer/.vscode-server ]; then
    echo "VSCode Server installed" > /tmp/vscode_server_status.txt
    ls -la /home/developer/.vscode-server/bin/ > /tmp/vscode_server_versions.txt 2>&1 || echo "No versions" > /tmp/vscode_server_versions.txt
else
    echo "VSCode Server not installed" > /tmp/vscode_server_status.txt
    echo "" > /tmp/vscode_server_versions.txt
fi

# Check for remote extensions
if [ -d /home/developer/.vscode-server/extensions ]; then
    ls -1 /home/developer/.vscode-server/extensions/ > /tmp/remote_extensions.txt 2>&1
else
    echo "No remote extensions directory" > /tmp/remote_extensions.txt
fi

# Check for remote workspace
if [ -d /home/developer/projects ]; then
    ls -la /home/developer/projects/ > /tmp/remote_workspace_listing.txt 2>&1
    echo "Workspace exists" > /tmp/remote_workspace_status.txt
else
    echo "No workspace" > /tmp/remote_workspace_listing.txt
    echo "Workspace does not exist" > /tmp/remote_workspace_status.txt
fi

# Check if hello-server.js exists
if [ -f /home/developer/projects/hello-server.js ]; then
    cp /home/developer/projects/hello-server.js /tmp/hello_server_code.js 2>/dev/null
else
    echo "File not created" > /tmp/hello_server_code.js
fi

# Check for running Node.js process as developer user
ps aux | grep developer | grep node | grep -v grep > /tmp/remote_node_processes.txt 2>&1 || echo "No Node.js process found" > /tmp/remote_node_processes.txt

# Check for local Node.js process (should NOT exist)
ps aux | grep "^ga" | grep node | grep -v grep > /tmp/local_node_processes.txt 2>&1 || echo "No local Node.js process" > /tmp/local_node_processes.txt

# Export git-like system info for debugging
whoami > /tmp/current_user.txt 2>&1
hostname > /tmp/hostname.txt 2>&1

echo "✅ Export complete"
echo ""
echo "Exported files:"
echo "  • /tmp/ssh_config.txt"
echo "  • /tmp/vscode_server_status.txt"
echo "  • /tmp/remote_extensions.txt"
echo "  • /tmp/remote_workspace_status.txt"
echo "  • /tmp/hello_server_code.js"
echo "  • /tmp/remote_node_processes.txt"
echo ""