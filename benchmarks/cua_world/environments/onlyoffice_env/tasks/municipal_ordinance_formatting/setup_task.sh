#!/bin/bash
echo "=== Setting up Municipal Ordinance Formatting Task ==="

source /workspace/scripts/task_utils.sh

# Record start timestamp for anti-gaming verification
date +%s > /tmp/task_start_time.txt

cleanup_temp_files
kill_onlyoffice ga
sleep 1

# Create workspace and raw text file
WORKSPACE_DIR="/home/ga/Documents/TextDocuments"
sudo -u ga mkdir -p "$WORKSPACE_DIR"
RAW_TEXT_PATH="$WORKSPACE_DIR/raw_str_ordinance.txt"

cat > "$RAW_TEXT_PATH" << 'EOF'
ORDINANCE NO. 2026-04
REGULATION OF SHORT-TERM RENTALS

WHEREAS, the City Council finds it necessary to regulate short-term rentals to preserve neighborhood character while allowing property owners reasonable use of their properties;

NOW, THEREFORE, BE IT ORDAINED BY THE CITY COUNCIL:

Section 1: Definitions
"Short-Term Rental" means the rental of a residential dwelling unit for periods of fewer than 30 consecutive days.
"Owner" means the person or entity holding legal title to the property.

Section 2: Licensing Requirements
No person shall operate a Short-Term Rental without first obtaining a valid Short-Term Rental License from the City Clerk.
Licenses must be renewed annually and clearly displayed within the rental unit.

Section 3: Operational Standards
Maximum occupancy shall not exceed 2 persons per bedroom plus 2 additional persons.
Noise restrictions apply from 10:00 PM to 7:00 AM daily.
Trash must be stored in approved receptacles and not placed at the curb earlier than 12 hours before scheduled pickup.

Section 4: Penalties and Enforcement
Violations of this ordinance shall be subject to the following fine schedule:
Tier 1 Violation (Noise, Trash, Parking) - $250
Tier 2 Violation (Occupancy limit exceeded) - $500
Operating without a valid license - $1000
Three or more violations within a 12-month period - License Revocation

EFFECTIVE DATE: This ordinance shall take effect 30 days after its passage and publication.

Mayor Jane Doe
Attest: City Clerk John Smith
EOF

chown ga:ga "$RAW_TEXT_PATH"

# Start ONLYOFFICE Document Editor and open the text file
echo "Starting ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$RAW_TEXT_PATH' > /tmp/onlyoffice_task.log 2>&1 &"

# Wait for the window to appear
wait_for_window "ONLYOFFICE\|Desktop Editors" 30

# Maximize and focus the window
WID=$(get_onlyoffice_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Dismiss any immediate startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Capture the initial state screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="