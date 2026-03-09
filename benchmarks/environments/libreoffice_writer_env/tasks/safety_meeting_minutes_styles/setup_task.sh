#!/bin/bash
set -e
echo "=== Setting up Safety Meeting Minutes Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Create Documents directory
sudo -u ga mkdir -p /home/ga/Documents

# Generate the raw input document using python-docx
# This ensures we have a clean, style-free starting state
python3 << 'PYEOF'
from docx import Document
from docx.shared import Pt

doc = Document()

# Title (plain text)
doc.add_paragraph("Site 42 - Safety Meeting Minutes")

doc.add_paragraph("Date: October 12, 2023")
doc.add_paragraph("Time: 07:00 AM")
doc.add_paragraph("Location: Site Office Trailer")
doc.add_paragraph("")

# Section 1
doc.add_paragraph("Attendance")
doc.add_paragraph("Foreman: Mike Ross")
doc.add_paragraph("Safety Officer: Sarah Jenks")
doc.add_paragraph("Crew: T. Higgins, B. Smith, K. Johnson, M. Lee, D. Garcia")
doc.add_paragraph("")

# Section 2
doc.add_paragraph("Previous Incidents")
doc.add_paragraph("Discussed the minor slip-and-fall event near the north gate on Oct 10 due to mud accumulation.")
doc.add_paragraph("ACTION: Review incident report #882 and install gravel path at north gate entrance by Friday.")
doc.add_paragraph("")

# Section 3
doc.add_paragraph("Excavation Safety Review")
doc.add_paragraph("Phase 2 trenching begins next week. Soil classification checked as Type B. Sloping requirements reviewed (1:1).")
doc.add_paragraph("ACTION: Order 50ft of barrier tape and 10 new rebar caps before trenching begins.")
doc.add_paragraph("Reminded crew that ladders must be placed every 25 feet of lateral travel in trenches 4 feet or deeper.")
doc.add_paragraph("")

# Section 4
doc.add_paragraph("PPE Compliance")
doc.add_paragraph("Observed two workers without high-visibility vests during heavy equipment operation hours.")
doc.add_paragraph("ACTION: Conduct spot checks for PPE compliance twice daily for the next week.")
doc.add_paragraph("Gloves are required for all rebar handling tasks without exception.")
doc.add_paragraph("")

# Section 5
doc.add_paragraph("Upcoming Hazards")
doc.add_paragraph("Crane lift scheduled for Tuesday. Swing radius must be barricaded.")
doc.add_paragraph("ACTION: Schedule signalman training refresher for M. Lee prior to Tuesday lift.")
doc.add_paragraph("Weather forecast predicts heavy rain on Thursday; ensure pumps are serviced.")

doc.save("/home/ga/Documents/site_42_safety_minutes.docx")
print("Generated unformatted safety minutes document.")
PYEOF

# Fix permissions
chown ga:ga /home/ga/Documents/site_42_safety_minutes.docx
chmod 666 /home/ga/Documents/site_42_safety_minutes.docx

# Launch LibreOffice Writer
echo "Launching LibreOffice Writer..."
su - ga -c "DISPLAY=:1 libreoffice --writer --norestore /home/ga/Documents/site_42_safety_minutes.docx > /tmp/writer_launch.log 2>&1 &"

# Wait for window
wait_for_window "LibreOffice Writer" 60 || wait_for_window "site_42" 30

# Maximize and focus
wid=$(get_writer_window_id)
if [ -n "$wid" ]; then
    echo "Focusing window ID: $wid"
    focus_window "$wid"
    DISPLAY=:1 wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    
    # Dismiss any initial dialogs (like "Tip of the Day")
    sleep 2
    safe_xdotool ga :1 key Escape
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="