#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Navigate Back After Definition Task ==="

WORKSPACE_DIR="/home/ga/workspace/nav_task"
sudo -u ga mkdir -p "$WORKSPACE_DIR/utils"

# Create main.py with marker comment at target return position
cat > "$WORKSPACE_DIR/main.py" << 'EOF'
from utils.helpers import process_data

def implement_new_feature():
    # Fetch user input
    user_input = get_user_input()
    
    # <- WORK IN PROGRESS - original cursor position
    result = process_data(user_input)
    
    return result

def get_user_input():
    return input("Enter data: ")
EOF

# Create utils/helpers.py with function definition
cat > "$WORKSPACE_DIR/utils/helpers.py" << 'EOF'
def process_data(raw_data):
    """
    Process raw user input and return cleaned data.
    
    Args:
        raw_data: Unprocessed user input string
        
    Returns:
        Cleaned and validated data
    """
    # Function implementation
    cleaned = raw_data.strip().lower()
    validated = validate_input(cleaned)
    return validated

def validate_input(data):
    """Validate input data"""
    if not data:
        raise ValueError("Empty input")
    return data
EOF

# Create empty __init__.py for Python package
touch "$WORKSPACE_DIR/utils/__init__.py"

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Record expected return position for verifier
echo "6" > /tmp/nav_task_target_line.txt
echo "main.py" > /tmp/nav_task_target_file.txt
sudo chown ga:ga /tmp/nav_task_target_line.txt /tmp/nav_task_target_file.txt

# Open VSCode with workspace
echo "Opening VSCode with workspace..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 2

# Open main.py first
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR/main.py'" || true
sleep 2

# Now open helpers.py to simulate the post-F12 state
# This simulates that the user was in main.py, pressed F12, and is now viewing helpers.py
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR/utils/helpers.py'" || true
sleep 2

focus_vscode_window

# Record initial timestamp for main.py
touch /tmp/nav_task_start_time.txt
stat -c %Y "$WORKSPACE_DIR/main.py" > /tmp/nav_task_main_timestamp.txt 2>/dev/null || echo "0" > /tmp/nav_task_main_timestamp.txt

echo "=== Navigate Back After Definition Task Setup Complete ==="
echo "📝 Current state:"
echo "  - You were editing main.py at line 6"
echo "  - You pressed F12 to check process_data() definition"
echo "  - Now viewing utils/helpers.py"
echo ""
echo "📝 Instructions:"
echo "  - Press Alt+Left to navigate back to main.py"
echo "  - OR use menu: Go → Back"