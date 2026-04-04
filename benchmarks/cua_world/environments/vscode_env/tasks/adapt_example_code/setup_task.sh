#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Adapt Example Code Task ==="

WORKSPACE_DIR="/home/ga/workspace/datavalidator"
TASK_ASSETS="/workspace/tasks/adapt_example_code/assets"

# Create project structure
sudo -u ga mkdir -p "$WORKSPACE_DIR/pipeline"
sudo -u ga mkdir -p "$WORKSPACE_DIR/tests"
sudo -u ga mkdir -p "$WORKSPACE_DIR/docs"

# Copy asset files to workspace
echo "Copying project files..."

# Pipeline files
sudo -u ga cp "$TASK_ASSETS/pipeline/processor.py" "$WORKSPACE_DIR/pipeline/processor.py"
sudo -u ga cp "$TASK_ASSETS/pipeline/validator.py" "$WORKSPACE_DIR/pipeline/validator.py"
sudo -u ga cp "$TASK_ASSETS/pipeline/__init__.py" "$WORKSPACE_DIR/pipeline/__init__.py"

# Documentation with example
sudo -u ga cp "$TASK_ASSETS/docs/example_validator.py" "$WORKSPACE_DIR/docs/example_validator.py"

# Project files
sudo -u ga cp "$TASK_ASSETS/README.md" "$WORKSPACE_DIR/README.md"
sudo -u ga cp "$TASK_ASSETS/requirements.txt" "$WORKSPACE_DIR/requirements.txt"

# Set ownership
sudo chown -R ga:ga "$WORKSPACE_DIR"

# Initialize git repository
echo "Initializing git repository..."
cd "$WORKSPACE_DIR"
sudo -u ga git init
sudo -u ga git config user.name "GA User"
sudo -u ga git config user.email "ga@localhost"
sudo -u ga git add .
sudo -u ga git commit -m "Initial commit: data validator project"

# Install python-magic if not already installed
echo "Installing python-magic..."
sudo apt-get update -qq > /dev/null 2>&1
sudo apt-get install -y -qq python3-magic libmagic1 > /dev/null 2>&1 || echo "python-magic already available"

# Open VSCode with workspace
echo "Opening VSCode with workspace..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR' --new-window" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 2

# Open the two key files side by side
echo "Opening example and target files..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR/docs/example_validator.py'" &
sleep 2
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR/pipeline/validator.py'" &
sleep 2

focus_vscode_window

echo "=== Adapt Example Code Task Setup Complete ==="
echo "📝 Context:"
echo "  Example code: docs/example_validator.py (FastAPI web upload validator)"
echo "  Target file: pipeline/validator.py (CLI file validator - needs implementation)"
echo ""
echo "📝 Instructions:"
echo "  1. Examine the validation logic in docs/example_validator.py"
echo "  2. Adapt it into pipeline/validator.py's FileValidator class"
echo "  3. Implement validate() method with the three validation checks"
echo "  4. Implement get_validation_errors() method"
echo "  5. Remove FastAPI dependencies, work with Path objects"
echo "  6. Save the file when done (Ctrl+S)"