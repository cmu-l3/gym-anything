#!/bin/bash
set -e
echo "=== Setting up Business Letter Formatting task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

export DISPLAY=:1

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Create the unformatted draft document using python-docx
# We embed the python script here to ensure it's self-contained
cat > /tmp/create_draft.py << 'PYEOF'
from docx import Document
from docx.shared import Inches
import os

def create_draft():
    doc = Document()
    
    # Reset default style to ensure it's "raw" (often defaults to Calibri 11)
    style = doc.styles['Normal']
    style.font.name = 'Liberation Sans'  # Intentionally wrong font
    style.font.size = None               # Let it default (usually 11 or 12)

    paragraphs_text = [
        "Meridian Property Group, LLC",
        "4200 Westpark Drive, Suite 310",
        "Tysons Corner, VA 22102",
        "Tel: (703) 555-0184 | Fax: (703) 555-0192",
        "",
        "October 17, 2024",
        "",
        "Ms. Catherine Delacroix",
        "Belvedere Commercial Interiors, Inc.",
        "Suite 1450",
        "4200 Westpark Drive",
        "Tysons Corner, VA 22102",
        "",
        "Re: Notice of HVAC System Replacement — Building Common Areas and Tenant Suites, Phase 2",
        "",
        "Dear Ms. Delacroix,",
        "We are writing to inform you that Meridian Property Group, LLC has contracted with Dominion Mechanical Services to perform a complete replacement of the central HVAC system serving Building C at the Westpark Drive commercial complex. This project has been necessitated by the end-of-life status of the existing Carrier WeatherMaster 50XC rooftop units, which were originally installed during the 1998 base building construction and have experienced escalating maintenance costs over the past three fiscal years.",
        "Construction activities for Phase 2, which encompasses floors 12 through 18, are scheduled to commence on Monday, November 4, 2024 and are projected to conclude no later than Friday, December 20, 2024. During this period, work will be performed between the hours of 7:00 AM and 6:00 PM, Monday through Friday. Weekend work may be required during the final two weeks of the project to maintain the completion schedule; tenants will receive 48 hours advance notice of any weekend activities.",
        "Temporary heating and cooling will be provided through portable HVAC units staged on each affected floor. While Dominion Mechanical has assured us that indoor temperatures will be maintained within 3 degrees Fahrenheit of normal setpoints, you may experience brief fluctuations during changeover periods, typically lasting no more than 45 minutes per occurrence. We recommend that tenants with temperature-sensitive equipment or inventory contact our building engineering team at ext. 2240 to discuss supplemental cooling arrangements.",
        "Please be advised that access to the main freight elevator serving the north tower will be restricted to construction personnel between 6:00 AM and 9:00 AM daily throughout the project duration. Passenger elevators will remain fully operational. Additionally, the 14th floor common area restrooms will be temporarily closed from November 11 through November 22 while ductwork is rerouted; tenants on floor 14 may use the restroom facilities on floors 13 and 15 during this period.",
        "Meridian Property Group remains committed to minimizing disruption to your business operations during this essential capital improvement. Should you have any questions regarding the project scope, timeline, or potential impacts to your suite, please do not hesitate to contact our property management office at (703) 555-0184 or via email at building-ops@meridianpg.com. We will provide weekly progress updates via email every Friday beginning November 1.",
        "We appreciate your patience and cooperation as we work to improve the comfort and energy efficiency of the Westpark Drive complex for all tenants.",
        "",
        "Sincerely,",
        "",
        "",
        "Jonathan R. Whitfield",
        "Senior Property Manager",
        "Meridian Property Group, LLC",
        "",
        "cc: Robert Tanaka, Director of Facilities",
        "    Dominion Mechanical Services — Project Manager",
        "    Building C Tenant File"
    ]

    for text in paragraphs_text:
        doc.add_paragraph(text)

    # Set bad margins (1.25 inch default) to ensure agent has to change them
    for section in doc.sections:
        section.top_margin = Inches(1.25)
        section.bottom_margin = Inches(1.25)
        section.left_margin = Inches(1.25)
        section.right_margin = Inches(1.25)

    output_path = "/home/ga/Documents/tenant_notice_draft.docx"
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    doc.save(output_path)
    print(f"Draft document created: {output_path}")

if __name__ == "__main__":
    create_draft()
PYEOF

# Execute the python script to generate the file
python3 /tmp/create_draft.py
rm -f /tmp/create_draft.py

# Set ownership
chown ga:ga /home/ga/Documents/tenant_notice_draft.docx

# Clean up any previous run artifacts
rm -f /home/ga/Documents/tenant_notice_final.docx

# Kill any existing LibreOffice instances
pkill -f soffice 2>/dev/null || true
sleep 2

# Launch LibreOffice Writer with the draft document
echo "Launching LibreOffice Writer..."
su - ga -c "DISPLAY=:1 libreoffice --writer --norestore /home/ga/Documents/tenant_notice_draft.docx > /dev/null 2>&1 &"

# Wait for Writer window to appear
echo "Waiting for Writer window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "LibreOffice Writer"; then
        echo "Writer window detected."
        break
    fi
    sleep 1
done

# Maximize the window
sleep 2
DISPLAY=:1 wmctrl -r "LibreOffice Writer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Focus the window
DISPLAY=:1 wmctrl -a "LibreOffice Writer" 2>/dev/null || true

# Take initial state screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="