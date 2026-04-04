#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Fix Git Identity Leak Task ==="

WORKSPACE_DIR="/home/ga/workspace"
WORK_DIR="$WORKSPACE_DIR/work"
PERSONAL_DIR="$WORKSPACE_DIR/personal"

# Clean up any existing workspace
sudo -u ga rm -rf "$WORKSPACE_DIR"
sudo -u ga mkdir -p "$WORK_DIR/corporate-api"
sudo -u ga mkdir -p "$PERSONAL_DIR/oss-library"

# Remove any existing conditional git config to start fresh
sudo -u ga bash -c "sed -i '/includeIf/,+1d' /home/ga/.gitconfig 2>/dev/null || true"
sudo -u ga rm -f /home/ga/.gitconfig-work /home/ga/.gitconfig-personal

# Set global git config to work identity (this is the "wrong" default)
sudo -u ga git config --global user.name "Corporate Dev"
sudo -u ga git config --global user.email "dev@megacorp.com"

echo "Initializing work project (corporate-api)..."
cd "$WORK_DIR/corporate-api"
sudo -u ga git init

cat > README.md << 'EOF'
# Corporate API

Internal company REST API service.
EOF

sudo -u ga mkdir -p src
cat > src/app.py << 'EOF'
"""Corporate API application"""

def api_handler():
    """Handle API requests"""
    return {"status": "ok"}
EOF

sudo chown -R ga:ga "$WORK_DIR/corporate-api"
cd "$WORK_DIR/corporate-api"
sudo -u ga git add .
sudo -u ga git commit -m "Initial corporate API setup"

echo "Initializing personal project (oss-library) with WRONG identity..."
cd "$PERSONAL_DIR/oss-library"
sudo -u ga git init

cat > README.md << 'EOF'
# OSS Library

Open source utility library for data processing.
EOF

sudo -u ga mkdir -p src
cat > src/library.py << 'EOF'
"""Public utility library"""

def public_function():
    """A useful public function"""
    return "Hello from OSS"
EOF

sudo chown -R ga:ga "$PERSONAL_DIR/oss-library"
cd "$PERSONAL_DIR/oss-library"
sudo -u ga git add .

# This commit will have WORK email (the problem to fix!)
sudo -u ga git commit -m "Add public function"

# Verify the problematic commit was created
COMMIT_AUTHOR=$(cd "$PERSONAL_DIR/oss-library" && sudo -u ga git log -1 --format="%an <%ae>")
echo "❌ Problematic commit created: $COMMIT_AUTHOR"
echo "   (Should be personal identity, but shows work email)"

# Set ownership
sudo chown -R ga:ga "$WORKSPACE_DIR"

# Open VSCode with the personal project (where the problem is)
echo "Opening VSCode with personal project..."
su - ga -c "DISPLAY=:1 code '$PERSONAL_DIR/oss-library'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

# Open integrated terminal
echo "Opening integrated terminal..."
sleep 1
su - ga -c "DISPLAY=:1 xdotool key ctrl+grave" || true
sleep 2

echo "=== Fix Git Identity Leak Task Setup Complete ==="
echo "📝 Scenario:"
echo "   Your personal OSS project has a commit with your WORK email!"
echo "   Current commit author: $COMMIT_AUTHOR"
echo ""
echo "🎯 Tasks:"
echo "   1. Amend commit to use: Personal Dev <personal.dev@example.com>"
echo "   2. Set up conditional git config for automatic identity switching"
echo "   3. Create ~/.gitconfig-work and ~/.gitconfig-personal files"
echo ""
echo "📚 Hint: Use git commit --amend --author=\"...\" and git config includeIf"