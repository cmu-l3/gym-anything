#!/bin/bash
set -e
echo "=== Setting up Stoichiometric Combustion Task ==="

source /workspace/utils/task_utils.sh

# 1. Clean up previous results
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/task_start_time.txt 2>/dev/null || true

# 2. Record task start time
date +%s > /tmp/task_start_time.txt

# 3. Ensure USLCI database exists (for elementary flows)
# The agent needs elementary flows (Oxygen, CO2, Water) which are in USLCI.
# If not present, we should prompt or try to ensure it's available.
# The environment installs it to /opt/openlca_data/uslci_database.zip
# We will verify if a DB is already imported; if not, we rely on the agent or
# we could pre-import it. To keep the task focused on modeling, we'll assume
# the agent can use what's there or create flows if needed, but using existing flows is best.
# We won't force import here to allow flexibility, but we verify environment health.

DB_PATH=$(ensure_uslci_database)
if [ -n "$DB_PATH" ]; then
    echo "Existing database found at $DB_PATH"
else
    echo "No existing database found. Agent may need to create one or import USLCI."
fi

# 4. Launch OpenLCA
echo "Launching OpenLCA..."
launch_openlca 180

# 5. Maximize window
WID=$(get_openlca_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# 6. Create instructions file on Desktop (optional helper)
cat > /home/ga/Desktop/STOICHIOMETRY_DATA.txt <<EOF
Reaction: CH4 + 2 O2 -> CO2 + 2 H2O

Molar Masses:
  C = 12 g/mol
  H = 1 g/mol
  O = 16 g/mol

  CH4 = 16 g/mol
  O2  = 32 g/mol
  CO2 = 44 g/mol
  H2O = 18 g/mol

Goal: Model 1 kg of Methane combustion.
EOF
chmod +x /home/ga/Desktop/STOICHIOMETRY_DATA.txt

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="