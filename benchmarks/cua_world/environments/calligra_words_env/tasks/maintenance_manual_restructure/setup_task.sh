#!/bin/bash
set -euo pipefail

echo "=== Setting up Maintenance Manual Restructure Task ==="

source /workspace/scripts/task_utils.sh || true

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create required directories
install -d -o ga -g ga /home/ga/Documents
install -d -o ga -g ga /home/ga/Desktop

# Clean previous instances
kill_calligra_processes 2>/dev/null || true
rm -f /home/ga/Documents/hvac_maintenance_manual.odt
rm -f /home/ga/Desktop/manual_restructuring_guide.txt

# ------------------------------------------------------------------
# 1. Generate the Text Restructuring Guide
# ------------------------------------------------------------------
cat > /home/ga/Desktop/manual_restructuring_guide.txt << 'EOF'
HVAC MAINTENANCE MANUAL RESTRUCTURING GUIDE

1. DOCUMENT SEQUENCE
The manual sections are currently scrambled. You must rearrange the entire document (cut and paste the multi-paragraph sections) to match the following exact order:
1. Introduction and Safety Precautions
2. System Overview and Specifications
3. Monthly Inspection Procedures
4. Quarterly Maintenance Procedures
5. Semi-Annual Maintenance Procedures
6. Annual Maintenance Procedures
7. Troubleshooting Guide
8. Parts and Supplies Reference

2. HEADING HIERARCHY
- ALL of the 8 main section titles listed above MUST be formatted as Heading 1.
- Any maintenance sub-tasks (e.g., Filter Inspection, Coil Cleaning Procedure, Refrigerant Level Check, Belt and Bearing Inspection, Electrical Component Testing) MUST be formatted as Heading 2.

3. MAINTENANCE SCHEDULE TABLE
At the end of the "System Overview and Specifications" section, insert a table summarizing the schedule. The table must contain these 4 columns: Task, Frequency, Estimated Duration, Assigned To.
Include at least 6 of the following rows:
- Replace MERV Filters | Monthly | 15 mins | Field Tech
- Clear Condensate Drain | Monthly | 10 mins | Field Tech
- Inspect Drive Belts | Quarterly | 20 mins | Field Tech
- Lubricate Bearings | Quarterly | 15 mins | Field Tech
- Clean Condenser Coil | Semi-Annual | 45 mins | Senior Tech
- Check Refrigerant | Semi-Annual | 30 mins | Senior Tech
- Megohm Motor Test | Annual | 60 mins | Master Electrician
EOF
chown ga:ga /home/ga/Desktop/manual_restructuring_guide.txt

# ------------------------------------------------------------------
# 2. Generate the Scrambled ODT Document via Python
# ------------------------------------------------------------------
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.style import Style, TextProperties
from odf.text import P, H

doc = OpenDocumentText()

# Add a few broken/inconsistent styles to simulate the bad export
h3_style = Style(name="Heading_20_3", family="paragraph")
h3_style.addElement(TextProperties(fontsize="14pt", fontweight="bold"))
doc.automaticstyles.addElement(h3_style)

h2_style = Style(name="Heading_20_2", family="paragraph")
h2_style.addElement(TextProperties(fontsize="16pt", fontweight="bold"))
doc.automaticstyles.addElement(h2_style)

def add_h(text, level, stylename):
    doc.text.addElement(H(outlinelevel=level, stylename=stylename, text=text))

def add_p(text):
    doc.text.addElement(P(text=text))

# Section 1 (Scrambled) -> Should be 4th
add_p("Quarterly Maintenance Procedures")
add_p("Belt and Bearing Inspection")
add_p("Inspect all drive belts for wear, cracks, and proper tension. Lubricate fan bearings with approved lithium-based grease.")
add_p("Check the evaporator and condenser coils for debris accumulation.")
add_p("")

# Section 2 (Scrambled) -> Should be 6th
add_p("Annual Maintenance Procedures")
add_p("Electrical Component Testing")
add_p("Perform megohm testing on the compressor motor windings. Check all electrical connections for tightness and signs of pitting.")
add_p("")

# Section 3 (Scrambled) -> Should be 1st. Inconsistent: H3
add_h("Introduction and Safety Precautions", 3, "Heading_20_3")
add_p("This manual provides maintenance procedures for commercial rooftop HVAC units. Follow all lockout/tagout procedures before servicing equipment.")
add_p("")

# Section 4 (Scrambled) -> Should be 7th
add_p("Troubleshooting Guide")
add_p("If the compressor fails to start, verify thermostat calls for cooling and check the main contactor. Inspect the R-410A refrigerant lines for signs of oil leaks.")
add_p("")

# Section 5 (Scrambled) -> Should be 3rd
add_p("Monthly Inspection Procedures")
add_p("Filter Inspection")
add_p("Inspect and replace MERV-rated air filters as necessary. Ensure the condensate drain pan is clear of obstructions.")
add_p("")

# Section 6 (Scrambled) -> Should be 2nd
add_p("System Overview and Specifications")
add_p("The standard Carrier 48TM packaged unit features a scroll compressor and a microchannel condenser coil. It is designed for high-efficiency cooling in commercial applications.")
add_p("")

# Section 7 (Scrambled) -> Should be 8th
add_p("Parts and Supplies Reference")
add_p("Always use OEM replacement parts. Refer to the ASHRAE Standard 180 guidelines for component lifecycle expectations.")
add_p("")

# Section 8 (Scrambled) -> Should be 5th. Inconsistent: H2
add_h("Semi-Annual Maintenance Procedures", 2, "Heading_20_2")
add_p("Coil Cleaning Procedure")
add_p("Clean the condenser coil using a non-acidic foaming cleaner. Rinse thoroughly with water.")
add_p("Refrigerant Level Check")
add_p("Verify subcooling and superheat measurements to ensure proper refrigerant charge.")
add_p("")

doc.save("/home/ga/Documents/hvac_maintenance_manual.odt")
PYEOF
chown ga:ga /home/ga/Documents/hvac_maintenance_manual.odt

# ------------------------------------------------------------------
# 3. Launch Calligra Words
# ------------------------------------------------------------------
echo "Launching Calligra Words..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid calligrawords /home/ga/Documents/hvac_maintenance_manual.odt >/tmp/calligra.log 2>&1 < /dev/null &"

# Wait for Calligra to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "calligrawords\|hvac_maintenance_manual"; then
        echo "Calligra Words window detected."
        break
    fi
    sleep 1
done

# Maximize the window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "calligrawords\|hvac_maintenance_manual" | awk '{print $1; exit}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
    sleep 1
    # Dismiss potential startup dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
fi

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task Setup Complete ==="