#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up LOTO Procedure Formatting Task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

kill_calligra_processes

install -d -o ga -g ga /home/ga/Documents
install -d -o ga -g ga /home/ga/Desktop

rm -f /home/ga/Documents/LOTO_Cincinnati_Press.odt
rm -f /home/ga/Desktop/LOTO_Style_Guide.txt

# ------------------------------------------------------------------
# Create the LOTO Formatting Guide on the Desktop
# ------------------------------------------------------------------
cat > /home/ga/Desktop/LOTO_Style_Guide.txt << 'EOF'
LOTO PROCEDURE FORMATTING GUIDE

1. Title Block
   - The first three lines (Title, Machine, Location) must be Center aligned.

2. Section Headings
   - Remove the numbered prefixes (e.g., "1.0 ", "2.0 ").
   - Apply the 'Heading 1' style to the 5 main section titles (Purpose, Machine Specifications, Energy Source Inventory, Shutdown Sequence, Restoration to Normal Operations).

3. Energy Source Table
   - Convert the pipe-delimited (|) text under the "Energy Source Inventory" section into a proper 5-column table.
   - The table must include the header row.

4. Sequential Steps (Numbered Lists)
   - The steps under "Shutdown Sequence" (8 steps) and "Restoration to Normal Operations" (6 steps) must be formatted as proper Numbered Lists using the word processor's list feature. Do not just leave them as plain text with numbers typed in front.

5. Typography
   - Change the font family of the entire document to "Liberation Sans".
EOF
chown ga:ga /home/ga/Desktop/LOTO_Style_Guide.txt

# ------------------------------------------------------------------
# Create the unformatted LOTO document using odfpy
# ------------------------------------------------------------------
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.text import P

doc = OpenDocumentText()

lines = [
    "LOCKOUT / TAGOUT PROCEDURE",
    "Machine: Cincinnati 1000-Ton Hydraulic Press",
    "Location: Stamping Bay 4",
    "",
    "1.0 Purpose",
    "This procedure establishes the minimum requirements for the lockout of energy isolating devices whenever maintenance or servicing is done on the Cincinnati 1000-Ton Hydraulic Press. It shall be used to ensure that the machine is stopped, isolated from all potentially hazardous energy sources, and locked out before employees perform any servicing or maintenance.",
    "",
    "2.0 Machine Specifications",
    "Manufacturer: Cincinnati Incorporated",
    "Model: 1000-Series Hydraulic",
    "Asset ID: PR-1044",
    "Power: 480V, 3-Phase, 60Hz",
    "",
    "3.0 Energy Source Inventory",
    "Energy Type | Magnitude | Location | Isolation Device | Verification Method",
    "Electrical | 480V AC, 3-Phase | Main Control Panel | Disconnect Switch 1A | Attempt to start machine",
    "Hydraulic | 3000 PSI | Pump Unit Rear | Valve HV-2 | Verify gauge reads 0",
    "Pneumatic | 120 PSI | Air Drop 4 | Valve PV-1 | Release residual pressure",
    "Gravity / Mechanical | 20,000 lbs ram | Main Ram | Safety Blocks | Visually confirm blocks inserted",
    "",
    "4.0 Shutdown Sequence",
    "1. Notify all affected employees that the machine will be locked out for service.",
    "2. Shut down the machine using the normal stopping procedure (Main Control Panel -> Stop).",
    "3. Isolate electrical power at Disconnect Switch 1A and apply personal padlock and tag.",
    "4. Close hydraulic valve HV-2 and apply personal padlock and tag.",
    "5. Close pneumatic valve PV-1 and apply personal padlock and tag.",
    "6. Bleed residual pneumatic pressure by opening the bleeder valve on Air Drop 4.",
    "7. Insert safety blocks under the main ram to prevent gravity fall.",
    "8. Attempt to restart the machine at the main control panel to verify isolation. Return switch to OFF.",
    "",
    "5.0 Restoration to Normal Operations",
    "1. Check the machine and immediate area to ensure non-essential items have been removed.",
    "2. Ensure all employees are safely positioned or removed from the area.",
    "3. Verify that all controls are in the neutral or OFF position.",
    "4. Remove safety blocks from under the main ram.",
    "5. Remove personal padlocks and tags from all isolation devices.",
    "6. Re-energize the machine and notify affected employees that the machine is ready for use."
]

for line in lines:
    doc.text.addElement(P(text=line))

doc.save("/home/ga/Documents/LOTO_Cincinnati_Press.odt")
PYEOF

chown ga:ga /home/ga/Documents/LOTO_Cincinnati_Press.odt

# Launch Calligra Words directly with the document
echo "Launching Calligra Words..."
launch_calligra_document "/home/ga/Documents/LOTO_Cincinnati_Press.odt"

# Wait for application window to appear
if wait_for_window "Calligra Words\|LOTO_Cincinnati_Press" 30; then
    WID=$(get_calligra_window_id)
    if [ -n "$WID" ]; then
        focus_window "$WID"
        DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi
else
    echo "Warning: Calligra Words window not detected within timeout"
fi

# Dismiss any potential startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Capture initial screenshot
echo "Capturing initial state..."
sleep 2
take_screenshot /tmp/task_initial_state.png

echo "=== Task Setup Complete ==="