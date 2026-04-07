#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Spacecraft SOE Formatting Task ==="

kill_calligra_processes

install -d -o ga -g ga /home/ga/Documents

DOC_PATH="/home/ga/Documents/artemis_loi_soe.odt"
rm -f "$DOC_PATH"

# ------------------------------------------------------------------
# Create the unformatted Artemis LOI SOE using odfpy
# ALL content is plain P elements.
# ------------------------------------------------------------------
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.text import P

doc = OpenDocumentText()

def add_paragraph(text=""):
    doc.text.addElement(P(text=text))

# Title block
add_paragraph("Artemis V Lunar Orbit Insertion (LOI) Sequence of Events")
add_paragraph("Prepared by: Flight Activities Officer")
add_paragraph("Approved by: Flight Director")
add_paragraph("Mission Date: 2029-10-14")
add_paragraph("")

# Phase 1
add_paragraph("Phase 1: Pre-Burn Configuration")
add_paragraph("This phase covers the initial system configuration leading up to the T-2 hour milestone. All systems must be transitioned from transit mode to active maneuvering mode.")
add_paragraph("CRITICAL GO/NO-GO: Flight Director polls for Phase 1 Initiation.")
add_paragraph("Verify propulsion system isolation status before proceeding.")
add_paragraph("[COMMAND: CMD_PRP_ISOL_CHK]")
add_paragraph("WARNING: Failure to verify propellant line pressure before pre-pressurization will result in catastrophic overpressure and loss of vehicle.")
add_paragraph("Initiate helium pressurization sequence.")
add_paragraph("[COMMAND: CMD_HE_PRESS_INIT]")
add_paragraph("Confirm thermal control system is operating in high-rejection mode.")
add_paragraph("[COMMAND: CMD_TCS_RAD_DEPLOY]")
add_paragraph("")

# Timeline block (intended for table conversion)
add_paragraph("Timeline of Operations")
add_paragraph("Time | Event | Subsystem | Status")
add_paragraph("T-02:00:00 | Crew configures suits | ECLSS | Pending")
add_paragraph("T-01:30:00 | Maneuver to LOI attitude | GNC | Pending")
add_paragraph("T-00:45:00 | Star tracker update | NAV | Pending")
add_paragraph("T-00:15:00 | Engine chilldown | PROP | Pending")
add_paragraph("T-00:05:00 | Terminal count auto-sequence | CDH | Pending")
add_paragraph("T-00:00:00 | LOI Ignition | PROP | Pending")
add_paragraph("")

# Phase 2
add_paragraph("Phase 2: Attitude Control and Ignition")
add_paragraph("This phase covers the terminal countdown, engine chilldown, and the main engine burn for lunar orbit insertion.")
add_paragraph("CRITICAL GO/NO-GO: Flight Director polls for LOI Ignition Auto-Sequence.")
add_paragraph("Engage the Reaction Control System (RCS) for pitch/yaw stabilization.")
add_paragraph("[COMMAND: CMD_RCS_ENABLE_AUTO]")
add_paragraph("WARNING: If RCS thruster degradation exceeds 15% during pre-ignition checks, abort auto-sequence and revert to manual attitude hold.")
add_paragraph("Commence main engine liquid oxygen and liquid hydrogen chilldown procedure.")
add_paragraph("[COMMAND: CMD_ENG_CHILL_START]")
add_paragraph("Wait for temperature sensors to indicate nominal chill state.")
add_paragraph("[COMMAND: CMD_ENG_TEMP_VERIFY]")
add_paragraph("Start the auto-sequence timer at T-5 minutes.")
add_paragraph("")

# Phase 3
add_paragraph("Phase 3: Post-Burn and Telemetry Acquisition")
add_paragraph("This phase covers engine shutdown, orbit verification, and transitioning to lunar orbit coast mode.")
add_paragraph("At LOI + 00:12:00, confirm main engine cutoff (MECO).")
add_paragraph("[COMMAND: CMD_ENG_CUTOFF_CONFIRM]")
add_paragraph("CRITICAL GO/NO-GO: Flight Dynamics Officer confirms achieved lunar orbit parameters.")
add_paragraph("Secure propulsion system and close isolation valves.")
add_paragraph("[COMMAND: CMD_PRP_ISOL_VLV_CLOSE]")
add_paragraph("Re-establish high-gain antenna tracking with Deep Space Network.")
add_paragraph("")

doc.save("/home/ga/Documents/artemis_loi_soe.odt")
PYEOF

chown ga:ga "$DOC_PATH"
chmod 644 "$DOC_PATH"

echo "Document created at $DOC_PATH"

# Record start time for verification
date +%s > /tmp/task_start_time.txt

# Launch Calligra Words in the background
echo "Launching Calligra Words..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid calligrawords '$DOC_PATH' >/tmp/calligra_task.log 2>&1 < /dev/null &"

# Wait for the window to appear
echo "Waiting for Calligra Words window..."
if wait_for_window "Calligra Words" 30; then
    WID=$(wmctrl -l | grep -i "Calligra Words" | awk '{print $1; exit}')
    if [ -n "$WID" ]; then
        # Maximize and focus
        DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        focus_window "$WID"
        sleep 1
    fi
else
    echo "Warning: Calligra Words window not found within timeout."
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="