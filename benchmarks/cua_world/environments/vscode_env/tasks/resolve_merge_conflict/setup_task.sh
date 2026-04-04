#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Merge Conflict Resolution Task ==="

WORKSPACE_DIR="/home/ga/workspace/pricing-app"

# Clean up any existing workspace
if [ -d "$WORKSPACE_DIR" ]; then
    echo "Cleaning up existing workspace..."
    sudo rm -rf "$WORKSPACE_DIR"
fi

sudo -u ga mkdir -p "$WORKSPACE_DIR"
cd "$WORKSPACE_DIR"

# Initialize Git repository
echo "Initializing Git repository..."
sudo -u ga git init
sudo -u ga git config user.name "GA User"
sudo -u ga git config user.email "ga@localhost"

# Create initial project structure
echo "Creating initial commit..."
sudo -u ga mkdir -p src

cat > "$WORKSPACE_DIR/src/utils.py" << 'EOF'
"""Pricing utilities"""

def calculate_price(base):
    """Calculate final price"""
    return base
EOF

cat > "$WORKSPACE_DIR/src/config.py" << 'EOF'
"""Configuration settings"""

DEFAULT_TIMEOUT = 10
EOF

cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Pricing Application

A simple pricing calculator with discount and tax support.
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Make initial commit
cd "$WORKSPACE_DIR"
sudo -u ga git add .
sudo -u ga git commit -m "Initial commit: basic pricing structure"

# Create and switch to main branch (for newer Git versions)
sudo -u ga git branch -M main 2>/dev/null || true

# Create changes on main branch (incoming changes)
echo "Creating main branch changes..."
cat > "$WORKSPACE_DIR/src/utils.py" << 'EOF'
"""Pricing utilities"""

def calculate_price(base, discount, tax_rate):
    """Calculate final price with discount and tax
    
    Args:
        base: Base price
        discount: Discount percentage (0-100)
        tax_rate: Tax rate as decimal (e.g., 0.08 for 8%)
    
    Returns:
        Final price after discount and tax
    """
    discounted = base * (1 - discount / 100)
    final = discounted * (1 + tax_rate)
    return final
EOF

cat > "$WORKSPACE_DIR/src/config.py" << 'EOF'
"""Configuration settings"""

# Production-ready timeout values
DEFAULT_TIMEOUT = 60
MAX_RETRIES = 5
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"
sudo -u ga git add .
sudo -u ga git commit -m "Add tax calculation and update config for production"

# Create feature branch from initial commit (before main branch changes)
echo "Creating feature branch with conflicting changes..."
sudo -u ga git checkout -b feature-pricing HEAD~1

# Make conflicting changes on feature branch
cat > "$WORKSPACE_DIR/src/utils.py" << 'EOF'
"""Pricing utilities"""

def calculate_price(base, discount):
    """Calculate price with discount
    
    Args:
        base: Base price
        discount: Discount percentage (0-100)
    
    Returns:
        Discounted price
    """
    return base * (1 - discount / 100)
EOF

cat > "$WORKSPACE_DIR/src/config.py" << 'EOF'
"""Configuration settings"""

# Development timeout values
DEFAULT_TIMEOUT = 30
MAX_RETRIES = 3
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"
sudo -u ga git add .
sudo -u ga git commit -m "Add discount calculation feature"

# Attempt merge to create conflict state
echo "Creating merge conflict..."
sudo -u ga git merge main --no-commit --no-ff 2>&1 || {
    echo "✅ Merge conflicts created as expected"
}

# Verify conflict state was created
if sudo -u ga git status | grep -q "Unmerged paths"; then
    echo "✅ Repository is in conflicted state"
else
    echo "⚠️ Warning: Expected conflict state not detected"
fi

# List conflicted files for debugging
echo "Conflicted files:"
sudo -u ga git status --short

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Open VSCode in the conflicted repository
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

# Give VSCode time to detect Git state and show conflict indicators
sleep 2

echo "=== Merge Conflict Resolution Task Setup Complete ==="
echo "📝 Repository state:"
echo "  - Branch: feature-pricing"
echo "  - Merge in progress: main -> feature-pricing"
echo "  - Conflicted files: src/utils.py, src/config.py"
echo ""
echo "📝 Instructions:"
echo "  1. Open Source Control panel (Ctrl+Shift+G)"
echo "  2. Click on conflicted file: src/utils.py"
echo "  3. Review conflict: main adds tax_rate parameter"
echo "  4. Accept Incoming Change (main version)"
echo "  5. Save file (Ctrl+S)"
echo "  6. Click on conflicted file: src/config.py"
echo "  7. Accept Incoming Change (main has better values)"
echo "  8. Save file (Ctrl+S)"
echo "  9. Stage all resolved files (+ icon)"
echo "  10. Commit the merge (checkmark icon)"