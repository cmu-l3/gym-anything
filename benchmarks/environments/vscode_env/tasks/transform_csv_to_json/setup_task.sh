#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up CSV to JSON Transformation Task ==="

WORKSPACE_DIR="/home/ga/workspace/data_migration"
TASK_ASSETS="/workspace/tasks/transform_csv_to_json/assets"

# Create workspace directory
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Copy CSV file with employee data
if [ -f "$TASK_ASSETS/employee_access.csv" ]; then
    sudo -u ga cp "$TASK_ASSETS/employee_access.csv" "$WORKSPACE_DIR/"
    echo "✅ Copied employee_access.csv to workspace"
else
    echo "❌ ERROR: employee_access.csv not found in assets"
    exit 1
fi

# Copy README with detailed instructions
if [ -f "$TASK_ASSETS/README.md" ]; then
    sudo -u ga cp "$TASK_ASSETS/README.md" "$WORKSPACE_DIR/"
    echo "✅ Copied README.md to workspace"
else
    echo "⚠️ Warning: README.md not found in assets"
fi

# Create empty output file placeholder
sudo -u ga touch "$WORKSPACE_DIR/access_control.json"

# Set proper ownership
sudo chown -R ga:ga "$WORKSPACE_DIR"

# Open VSCode in the workspace
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

# Open the CSV file for examination
sleep 1
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR/employee_access.csv'" &
sleep 1

# Open the README
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR/README.md'" &
sleep 1

echo "=== CSV to JSON Transformation Task Setup Complete ==="
echo "📁 Workspace: $WORKSPACE_DIR"
echo "📄 Input: employee_access.csv (15 rows)"
echo "📄 Output: access_control.json (to be created)"
echo ""
echo "📝 Instructions:"
echo "  1. Examine employee_access.csv structure"
echo "  2. Read README.md for detailed requirements"
echo "  3. Write a transformation script (Python/Node.js/any language)"
echo "  4. Parse CSV and build nested JSON structure"
echo "  5. Handle edge cases: multiple roles per employee, quoted fields, whitespace"
echo "  6. Save output to access_control.json"
echo "  7. Validate all 15 CSV rows are represented"