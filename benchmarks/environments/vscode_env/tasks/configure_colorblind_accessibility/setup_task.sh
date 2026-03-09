#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Colorblind Accessibility Configuration Task ==="

# Create workspace with test files
WORKSPACE_DIR="/home/ga/workspace/accessibility_test"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create Python file with intentional errors for testing error highlighting
cat > "$WORKSPACE_DIR/test_file_with_errors.py" << 'EOF'
# This file has intentional errors to test error highlighting visibility

def calculate_sum(a, b):
    # Missing return statement - should show error
    result = a + b

def process_data(items)
    # Missing colon - syntax error
    for item in items:
        print(item)

# Undefined variable - should show error
print(undefined_variable)

# Incorrect indentation
def another_function():
print("This is incorrectly indented")

# Type error
x = "5"
y = x + 10  # TypeError: can't concatenate str and int
EOF

# Create test git repository with changes
TEST_REPO="$WORKSPACE_DIR/test_repo"
sudo -u ga mkdir -p "$TEST_REPO"
cd "$TEST_REPO"
sudo -u ga git init
sudo -u ga git config user.name "Test User"
sudo -u ga git config user.email "test@localhost"

# Create initial file and commit
cat > "$TEST_REPO/sample.py" << 'EOF'
def old_function():
    print("This line will be removed")
    print("This line stays")
EOF

sudo chown -R ga:ga "$TEST_REPO"
cd "$TEST_REPO"
sudo -u ga git add .
sudo -u ga git commit -m "Initial commit"

# Modify file to create diff
cat > "$TEST_REPO/sample.py" << 'EOF'
def new_function():
    print("This is a new line - should show in blue, not green")
    print("This line stays")
    print("Another new line - should show in blue")
EOF

# Create README with terminal test commands
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Colorblind Accessibility Test Workspace

## Terminal Color Test Commands

After configuring terminal colors, test them with:
