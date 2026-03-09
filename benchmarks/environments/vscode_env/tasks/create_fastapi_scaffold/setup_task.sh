#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Create FastAPI Scaffold Task ==="

# Create empty workspace directory
WORKSPACE_DIR="/home/ga/workspace/notification_service"
echo "Creating workspace directory: $WORKSPACE_DIR"

# Remove if exists to ensure clean state
if [ -d "$WORKSPACE_DIR" ]; then
    echo "Removing existing workspace..."
    sudo rm -rf "$WORKSPACE_DIR"
fi

# Create empty directory
sudo -u ga mkdir -p "$WORKSPACE_DIR"
sudo chown -R ga:ga "$WORKSPACE_DIR"

# Verify directory is empty
file_count=$(ls -A "$WORKSPACE_DIR" | wc -l)
if [ "$file_count" -eq 0 ]; then
    echo "✅ Workspace directory is empty and ready"
else
    echo "⚠️ Warning: Workspace directory is not empty (has $file_count items)"
fi

# Open VSCode at the workspace
echo "Opening VSCode at workspace..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

# Open integrated terminal to make file creation easier
echo "Opening integrated terminal..."
su - ga -c "DISPLAY=:1 xdotool key --delay 200 ctrl+grave" || true
sleep 2

echo "=== Create FastAPI Scaffold Task Setup Complete ==="
echo ""
echo "📝 Task Instructions:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Create a complete FastAPI microservice project structure with:"
echo ""
echo "📁 Directory Structure:"
echo "  notification_service/"
echo "  ├── src/          (source code)"
echo "  ├── tests/        (test files)"
echo "  └── docs/         (documentation)"
echo ""
echo "📄 Required Files (7+ files):"
echo "  1. src/__init__.py           - Package marker (can be empty)"
echo "  2. src/main.py               - FastAPI app with health endpoint"
echo "  3. tests/__init__.py         - Test package marker"
echo "  4. tests/test_main.py        - Test file with test functions"
echo "  5. .gitignore                - Python exclusions"
echo "  6. Dockerfile                - Container config"
echo "  7. pyproject.toml            - Project metadata"
echo "  8. README.md                 - Project documentation"
echo ""
echo "🔧 Key Requirements:"
echo "  • src/main.py must have FastAPI app and /health endpoint"
echo "  • pyproject.toml must list 'fastapi' as dependency"
echo "  • .gitignore must have Python patterns (__pycache__, *.pyc, etc.)"
echo "  • Dockerfile must have FROM and CMD instructions"
echo "  • All Python files must have valid syntax"
echo ""
echo "💡 Tip: Use File Explorer (Ctrl+Shift+E) or terminal commands"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"