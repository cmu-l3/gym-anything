#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Configure Conditional Git Identity Task ==="

WORKSPACE_DIR="/home/ga/workspace"
PERSONAL_DIR="$WORKSPACE_DIR/personal-projects/my-oss-lib"
COMPANY_DIR="$WORKSPACE_DIR/company-work/proprietary-app"

# Create directory structure
sudo -u ga mkdir -p "$PERSONAL_DIR"
sudo -u ga mkdir -p "$COMPANY_DIR"

# Set a default global git identity (that should be overridden)
sudo -u ga git config --global user.name "Default User"
sudo -u ga git config --global user.email "default@generic.com"

# Remove any existing conditional includes from previous runs
sudo -u ga bash -c "
if [ -f ~/.gitconfig ]; then
    # Create backup
    cp ~/.gitconfig ~/.gitconfig.backup
    # Remove any existing includeIf sections (simple approach - just remove the default includes)
    sed -i '/includeIf.*personal-projects/,+1d' ~/.gitconfig || true
    sed -i '/includeIf.*company-work/,+1d' ~/.gitconfig || true
fi
"

# Remove old include files if they exist
sudo -u ga rm -f /home/ga/.config/git/personal-identity.inc
sudo -u ga rm -f /home/ga/.config/git/company-identity.inc

# Initialize personal project repository
cd "$PERSONAL_DIR"
sudo -u ga git init

cat > "$PERSONAL_DIR/README.md" << 'EOF'
# My Open Source Library

This is a personal open-source project.
Commits here should use personal email.
EOF

cat > "$PERSONAL_DIR/main.py" << 'EOF'
def hello():
    """Personal open-source project"""
    return "Hello from OSS!"
EOF

sudo chown -R ga:ga "$PERSONAL_DIR"

# Initialize company project repository
cd "$COMPANY_DIR"
sudo -u ga git init

cat > "$COMPANY_DIR/README.md" << 'EOF'
# Proprietary Application

This is company proprietary code.
Commits here should use company email.
EOF

cat > "$COMPANY_DIR/app.py" << 'EOF'
def process():
    """Company proprietary code"""
    return "Company application"
EOF

sudo chown -R ga:ga "$COMPANY_DIR"

# Open VSCode with the workspace root
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR'" &
wait_for_vscode 25
wait_for_window "Visual Studio Code" 35

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

# Open integrated terminal to help agent get started
echo "Opening integrated terminal..."
sleep 2
su - ga -c "DISPLAY=:1 xdotool key ctrl+grave" || true
sleep 2

echo "=== Configure Conditional Git Identity Task Setup Complete ==="
echo "📝 Workspace structure:"
echo "  $PERSONAL_DIR (should use personal email)"
echo "  $COMPANY_DIR (should use company email)"
echo ""
echo "📝 Instructions:"
echo "  1. Create ~/.config/git/personal-identity.inc with personal email"
echo "  2. Create ~/.config/git/company-identity.inc with company email"
echo "  3. Add conditional includes to ~/.gitconfig"
echo "  4. Verify with: cd <dir> && git config user.email"