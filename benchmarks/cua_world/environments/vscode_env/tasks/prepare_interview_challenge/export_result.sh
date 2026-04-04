#!/bin/bash
# set -euo pipefail

echo "=== Exporting Prepare Interview Challenge Result ==="

WORKSPACE_DIR="/home/ga/workspace/interview_challenge"

# Save all open files in VSCode
echo "Saving all files..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key --delay 100 ctrl+shift+s" 2>/dev/null || true
sleep 2

# Also try regular save
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key --delay 100 ctrl+s" 2>/dev/null || true
sleep 1

# Export directory tree structure to /tmp for debugging
if [ -d "$WORKSPACE_DIR" ]; then
    echo "Workspace structure:"
    tree -a "$WORKSPACE_DIR" 2>/dev/null || find "$WORKSPACE_DIR" -type f -o -type d | sort
    
    # Create a manifest of all files
    find "$WORKSPACE_DIR" -type f > /tmp/interview_files_manifest.txt 2>/dev/null || true
    echo "File manifest saved to /tmp/interview_files_manifest.txt"
else
    echo "⚠️ Workspace directory not found: $WORKSPACE_DIR"
fi

echo "✅ Export complete"
echo "Workspace location: $WORKSPACE_DIR"