#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Tech Rider Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
sudo -u ga mkdir -p /home/ga/Documents/results

# Generate the raw tech rider document using python-docx
python3 << 'PYEOF'
from docx import Document
from docx.shared import Pt, Inches

doc = Document()

# Set initial normal margins (1 inch)
for section in doc.sections:
    section.top_margin = Inches(1.0)
    section.bottom_margin = Inches(1.0)
    section.left_margin = Inches(1.0)
    section.right_margin = Inches(1.0)

# Title (Normal style, left-aligned)
doc.add_paragraph("THE MIDNIGHT ECHO - 2026 WORLD TOUR TECHNICAL RIDER")
doc.add_paragraph("Venue Technical Advance Document")
doc.add_paragraph("")

# Section 1
doc.add_paragraph("1. AUDIO SPECIFICATIONS")
doc.add_paragraph("FOH console must be a DiGiCo SD12 or Yamaha Rivage PM7. PA must be L-Acoustics K1/K2, d&b audiotechnik KSL/J-Series, or Meyer Sound Panther, capable of 115dB C-Weighted at FOH without limiting.")
doc.add_paragraph("CRITICAL: Venue must provide a dedicated 30A isolated ground circuit at FOH for the band's touring rack. Do not share this circuit with lighting or video.")

doc.add_paragraph("")

# Section 2
doc.add_paragraph("2. LIGHTING & VIDEO")
doc.add_paragraph("The touring lighting package consists of a floor package requiring a 200A 3-phase service upstage center. Video wall is ground-stacked and requires an independent 100A 3-phase service.")
doc.add_paragraph("CRITICAL: Hazers must be allowed for the duration of the performance. Venue must isolate fire alarms in the main room during the show.")

doc.add_paragraph("")

# Section 3
doc.add_paragraph("3. BACKLINE REQUIREMENTS")
doc.add_paragraph("If backline is being provided by the local promoter, we require: 1x Ampeg SVT-VR classic head, 1x Ampeg 8x10 cabinet, 2x Fender Twin Reverb reissues, and a DW Collector's Series drum kit (22, 10, 12, 16).")
doc.add_paragraph("CRITICAL: All backline power must be set to 120V / 60Hz. If advancing internationally, step-down transformers must be rated for at least 2000W.")

doc.add_paragraph("")

# Section 4
doc.add_paragraph("4. INPUT LIST")
doc.add_paragraph("The following is the standard 24-channel festival patch:")
doc.add_paragraph("1, Kick In, Beta 91A, Gate")
doc.add_paragraph("2, Kick Out, Beta 52, -")
doc.add_paragraph("3, Snare Top, SM57, -")
doc.add_paragraph("4, Snare Bottom, SM57, Phase reverse")
doc.add_paragraph("5, Hi-Hat, SM81, HPF")
doc.add_paragraph("6, Tom 1, e604, Gate")
doc.add_paragraph("7, Tom 2, e604, Gate")
doc.add_paragraph("8, Floor Tom, e604, Gate")
doc.add_paragraph("9, Ride, SM81, HPF")
doc.add_paragraph("10, OH L, C414, -")
doc.add_paragraph("11, OH R, C414, -")
doc.add_paragraph("12, Bass DI, Radial J48, Phantom Power")
doc.add_paragraph("13, Bass Mic, RE20, -")
doc.add_paragraph("14, Guitar 1 L, SM57, -")
doc.add_paragraph("15, Guitar 1 R, e609, -")
doc.add_paragraph("16, Guitar 2 L, SM57, -")
doc.add_paragraph("17, Guitar 2 R, e609, -")
doc.add_paragraph("18, Keys L, Radial JDI, -")
doc.add_paragraph("19, Keys R, Radial JDI, -")
doc.add_paragraph("20, Tracks L, Radial ProD2, -")
doc.add_paragraph("21, Tracks R, Radial ProD2, -")
doc.add_paragraph("22, Lead Vocal, e935, Compress heavily")
doc.add_paragraph("23, BG Vocal 1, SM58, -")
doc.add_paragraph("24, BG Vocal 2, SM58, -")

doc.add_paragraph("")

# Section 5
doc.add_paragraph("5. HOSPITALITY")
doc.add_paragraph("The band requires access to the dressing rooms at least 4 hours before doors. Please provide the following upon load-in:")
doc.add_paragraph("* 24 bottles of spring water (not chilled)")
doc.add_paragraph("* 1 large deli tray for 6 people (must include vegetarian options)")
doc.add_paragraph("* Assorted fresh fruit (bananas, apples, oranges)")
doc.add_paragraph("* 12 local craft beers")
doc.add_paragraph("* Freshly brewed hot coffee and tea assortment")
doc.add_paragraph("* 6 clean black stage towels")

doc.save("/home/ga/Documents/raw_tech_rider.docx")
PYEOF

sudo chown ga:ga /home/ga/Documents/raw_tech_rider.docx
sudo chmod 644 /home/ga/Documents/raw_tech_rider.docx

# Kill existing WPS instances
pkill -f wps 2>/dev/null || true
sleep 1

# Launch WPS Writer with the document
echo "Launching WPS Writer..."
su - ga -c "DISPLAY=:1 wps /home/ga/Documents/raw_tech_rider.docx &"

# Wait for WPS Window
wait_for_window "WPS Writer" 30

# Maximize and focus
WID=$(get_wps_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 2
    
    # Dismiss potential EULA/Tip dialogs
    dismiss_wps_dialogs || true
    focus_window "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="