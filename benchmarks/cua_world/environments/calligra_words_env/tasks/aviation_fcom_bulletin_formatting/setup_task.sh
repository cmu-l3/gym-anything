#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Aviation FCOM Bulletin Formatting Task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure clean state
kill_calligra_processes
install -d -o ga -g ga /home/ga/Documents
install -d -o ga -g ga /home/ga/Desktop

rm -f /home/ga/Documents/b737_winter_ops_bulletin.odt
rm -f /home/ga/Desktop/fcom_style_guide.txt

# ------------------------------------------------------------------
# 1. Create the FCOM Style Guide on the Desktop
# ------------------------------------------------------------------
cat > /home/ga/Desktop/fcom_style_guide.txt << 'EOF'
FCOM BULLETIN FORMATTING REQUIREMENTS

Aviation documentation requires strict adherence to visual standards so flight crews can rapidly identify critical information during high-workload operations. Apply the following formatting:

1. HEADER (The top 4 lines: Title, Subject, Fleet, Date)
   - Alignment: Right-aligned
   - Font weight: Bold

2. SECTION HEADINGS (e.g., "1. Introduction", "2. Engine Anti-Ice Operation")
   - Must be formatted using the standard "Heading 1" style.

3. WARNING PARAGRAPHS (Any paragraph starting with "WARNING:")
   - Alignment: Centered
   - Font weight: Bold
   - Margins: Increase both the Left and Right margins by at least 1.0 inch (2.5 cm) so the text is visibly compressed in the center of the page.

4. CAUTION PARAGRAPHS (Any paragraph starting with "CAUTION:")
   - Alignment: Left-aligned (or default)
   - Font style: Italicized
   - Margins: Increase ONLY the Left margin by at least 0.5 inches (1.25 cm). Do not increase the right margin.

5. HOLDOVER TIMES DATA
   - The plaintext holdover times matrix in Section 3 must be converted into a formal Table.

6. PRE-TAKEOFF CONTAMINATION CHECK PROCEDURE
   - The 5 numbered steps in Section 4 must be converted into a formal Numbered List (do not just leave them as plain paragraphs that happen to start with numbers).
EOF
chown ga:ga /home/ga/Desktop/fcom_style_guide.txt

# ------------------------------------------------------------------
# 2. Create the raw unformatted .odt document
# ------------------------------------------------------------------
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.text import P

doc = OpenDocumentText()

def add_paragraph(text=""):
    doc.text.addElement(P(text=text))

# -- Header --
add_paragraph("FLIGHT CREW OPERATIONS MANUAL BULLETIN")
add_paragraph("Subject: Winter Operations and De-Icing")
add_paragraph("Fleet: B737-800")
add_paragraph("Date: November 1, 2025")
add_paragraph("")

# -- Section 1 --
add_paragraph("1. Introduction")
add_paragraph("This bulletin outlines revised winter operations procedures following recent regulatory changes regarding holdover times and engine anti-ice usage. Compliance is mandatory for all flight crews operating the B737 fleet during icing conditions.")
add_paragraph("")

# -- Section 2 --
add_paragraph("2. Engine Anti-Ice Operation")
add_paragraph("CAUTION: Engine anti-ice must be turned on during all ground and flight operations when icing conditions exist or are anticipated, except during climb and cruise when the temperature is below -40°C SAT.")
add_paragraph("The use of engine anti-ice affects engine performance and increases fuel consumption. However, failure to use it when required can result in ice accumulation on the engine cowl lip, which may be ingested into the engine.")
add_paragraph("WARNING: Do not use engine anti-ice when OAT is above 10°C. Doing so may cause severe engine damage or loss of thrust during critical phases of flight.")
add_paragraph("CAUTION: Observe engine limits. Maximum continuous EGT may be exceeded if anti-ice is used improperly at high thrust settings.")
add_paragraph("")

# -- Section 3 --
add_paragraph("3. Holdover Times (Type II/IV Fluid)")
add_paragraph("Holdover time begins when the final application of de-icing/anti-icing fluid commences. Crews must maintain awareness of precipitation intensity.")
add_paragraph("WARNING: Holdover times are guidelines only. A pre-takeoff contamination check is required if the holdover time has expired or if heavy snow is falling. Never takeoff with contaminated wings.")
add_paragraph("Fluid Type | Temperature Range | Snow | Freezing Drizzle | Light Freezing Rain")
add_paragraph("Type II | -3°C and above | 0:25 - 0:45 | 0:15 - 0:40 | 0:10 - 0:20")
add_paragraph("Type IV | -3°C and above | 0:45 - 1:15 | 0:25 - 0:50 | 0:15 - 0:30")
add_paragraph("Type IV | Below -3°C to -14°C | 0:20 - 0:45 | 0:15 - 0:30 | N/A")
add_paragraph("")

# -- Section 4 --
add_paragraph("4. Pre-Takeoff Contamination Check Procedure")
add_paragraph("When a contamination check is required, it must be performed from an optimal vantage point.")
add_paragraph("CAUTION: The check must be completed within 5 minutes prior to takeoff roll. If takeoff is delayed beyond 5 minutes, the check must be repeated.")
add_paragraph("1. Set parking brake.")
add_paragraph("2. Ensure cabin is secure and flight attendants are seated.")
add_paragraph("3. Conduct visual inspection of wing surfaces from the cabin windows.")
add_paragraph("4. Verify control surfaces are free of ice and snow.")
add_paragraph("5. If contamination is observed, return to the gate for secondary de-icing.")
add_paragraph("")

doc.save("/home/ga/Documents/b737_winter_ops_bulletin.odt")
PYEOF

chown ga:ga /home/ga/Documents/b737_winter_ops_bulletin.odt

# ------------------------------------------------------------------
# 3. Launch Application
# ------------------------------------------------------------------
launch_calligra_document "/home/ga/Documents/b737_winter_ops_bulletin.odt" "/tmp/calligra_launch.log"

# Wait for window and maximize
wait_for_window "Calligra Words" 30
WID=$(get_calligra_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# Dismiss startup tips if any
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot for reference
take_screenshot /tmp/task_initial_state.png

echo "=== Setup Complete ==="