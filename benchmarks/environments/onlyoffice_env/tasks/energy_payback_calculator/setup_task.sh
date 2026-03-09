#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Energy Payback Calculator Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Launch ONLYOFFICE Spreadsheet with blank file
# The agent will create the entire spreadsheet from scratch
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors --new:cell > /tmp/onlyoffice_energy_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_energy_task.log || true
fi

# Wait for window
if ! wait_for_window "ONLYOFFICE" 30; then
    echo "ERROR: ONLYOFFICE window did not appear"
fi

# Protect ONLYOFFICE from OOM killer
protect_onlyoffice_from_oom

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus ONLYOFFICE window
focus_onlyoffice_window

echo "=== Energy Payback Calculator Task Setup Complete ==="
echo "📝 Scenario: You're a homeowner evaluating a $8,500 energy-efficient window upgrade"
echo ""
echo "Given information:"
echo "  - Current monthly energy bill: $185"
echo "  - Expected reduction after upgrade: 30%"
echo "  - Total upgrade cost: $8,500"
echo ""
echo "Create a spreadsheet with the following structure:"
echo "  1. A1: 'Current Monthly Bill'        B1: 185"
echo "  2. A2: 'Reduction Percentage'        B2: 0.30"
echo "  3. A3: 'New Monthly Bill'            B3: =B1*(1-B2)"
echo "  4. A4: 'Monthly Savings'             B4: =B1-B3"
echo "  5. A5: 'Upgrade Cost'                B5: 8500"
echo "  6. A6: 'Payback Period (months)'     B6: =B5/B4"
echo "  7. Save as: /home/ga/Documents/Spreadsheets/energy_upgrade_analysis.xlsx"
echo ""
echo "Expected calculated results:"
echo "  - New Monthly Bill: ~$129.50"
echo "  - Monthly Savings: ~$55.50"
echo "  - Payback Period: ~153 months (~12.8 years)"