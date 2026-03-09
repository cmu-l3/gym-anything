#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Library Exploration Task ==="

WORKSPACE_DIR="/home/ga/workspace/library_task"
ASSETS_DIR="/workspace/tasks/explore_library_internals/assets"

# Create workspace
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create Python virtual environment
echo "Creating virtual environment..."
cd "$WORKSPACE_DIR"
sudo -u ga python3 -m venv venv
echo "✅ Virtual environment created"

# Install the fake datatools library
echo "Installing datatools library..."
DATATOOLS_SRC="$ASSETS_DIR/datatools"
if [ -d "$DATATOOLS_SRC" ]; then
    # Copy library source to temp location
    sudo -u ga cp -r "$DATATOOLS_SRC" /tmp/datatools_pkg
    cd /tmp/datatools_pkg
    
    # Install in editable mode
    sudo -u ga bash -c "source $WORKSPACE_DIR/venv/bin/activate && pip install -q -e ."
    
    echo "✅ datatools library installed"
else
    echo "⚠️ Warning: datatools source not found at $DATATOOLS_SRC"
fi

# Create the buggy data_processor.py file
cat > "$WORKSPACE_DIR/data_processor.py" << 'EOF'
"""
Data processing script that attempts to use the datatools library.

PROBLEM: This code doesn't work as expected!
The function seems to ignore some parameters or behaves differently than documented.

TODO: Navigate to the datatools library source code to understand what's actually happening.
Use Go to Definition (F12) or Ctrl+Click on process_data to jump to the source.
"""

import sys
sys.path.insert(0, '/home/ga/workspace/library_task/venv/lib/python3.10/site-packages')

from datatools import process_data

# Sample data
sample_data = [1, 2, 3, 4, 5]

# This code attempts to use the library but parameters seem wrong
# The documentation is unclear and behavior is unexpected
try:
    result = process_data(sample_data, mode='strict', ignore_errors=True)
    print(f"Result: {result}")
except Exception as e:
    print(f"Error: {e}")
    print("Something is wrong with the parameters!")
    print("Navigate to the library source to understand the real function signature.")

# TASK: 
# 1. Use F12 or Ctrl+Click on 'process_data' above to go to definition
# 2. Read the actual source code in the library
# 3. Understand what parameters it REALLY accepts
# 4. Create a new file 'test_datatools.py' with correct usage
EOF

# Create sample data file
cat > "$WORKSPACE_DIR/sample_data.json" << 'EOF'
[10, 20, 30, 40, 50]
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Open VSCode with the workspace and data_processor.py
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR' '$WORKSPACE_DIR/data_processor.py'" &
wait_for_vscode 25
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

# Give Python extension time to activate
sleep 3

echo "=== Library Exploration Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Examine data_processor.py (should be open)"
echo "  2. Use F12 or Ctrl+Click on 'process_data' to go to source"
echo "  3. Navigate through library files to find actual implementation"
echo "  4. Read the real function signature and parameters"
echo "  5. Create test_datatools.py with correct usage"
echo ""
echo "Workspace: $WORKSPACE_DIR"
echo "Virtual environment: $WORKSPACE_DIR/venv"