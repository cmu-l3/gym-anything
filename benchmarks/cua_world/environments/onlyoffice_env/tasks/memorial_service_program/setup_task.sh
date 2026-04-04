#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Memorial Service Program Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/MemorialService"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create fragmented notes file with scattered information from multiple sources
NOTES_PATH="$WORKSPACE_DIR/service_notes_fragments.txt"

cat > "$NOTES_PATH" << 'EOF'
MARGARET'S SERVICE - NOTES FROM FAMILY
=====================================

From David (text message 1/19 11:45pm):
I'll do the eulogy. Also Jennifer wants to read something and Emma (my daughter) 
wants to participate too. Pastor Chen will open and close.

From Sarah (email 1/20 8:30am):
Subject: Music for Aunt Margaret's service
I can sing "What a Wonderful World" - that was Aunt Margaret's favorite song. 
Should I do it before or after the eulogy? Let me know!

From Jennifer (text 1/20 9:15am):
Found the poem mom always loved - we should include this:

Do Not Stand at My Grave and Weep
Do not stand at my grave and weep
I am not there, I do not sleep.
I am a thousand winds that blow.
I am the diamond glints on snow.
I am the sunlight on ripened grain.
I am the gentle autumn rain.
When you awaken in the morning's hush
I am the swift uplifting rush
Of quiet birds in circled flight.
I am the soft stars that shine at night.
Do not stand at my grave and cry
I am not there, I did not die.

From David (text 1/20 10:30am):
Order should be: Pastor opens, then choir sings Amazing Grace, then I do eulogy, 
then the readings (Jennifer and Emma), then Sarah's song, then Pastor closes.

From funeral director (email 1/20 1:15pm):
Subject: Service Confirmation for Rodriguez
Service confirmed for Saturday, January 25, 2025 at 2:00 PM
Location: Riverside Community Chapel, 847 Oak Street
Please provide final program by end of today for printing.

RECEPTION UPDATE (text from Jennifer 1/20 2:00pm):
IMPORTANT!! Reception changed!! Now at Martinez Family Restaurant, 1240 River Road 
(Maria's place - she offered to host). Light refreshments will be served, 
vegetarian options available.

ZOOM INFO (email from nephew Carlos 1/20 2:30pm):
For remote family who can't travel:
Zoom link: https://zoom.us/j/5551234567?pwd=abc123XYZ
Tell people to contact family for meeting ID and passcode details if they need them.

DONATIONS (from Margaret's wishes - saved in her notes):
"Instead of flowers, please ask people to donate to Riverside Animal Shelter.
I volunteered there for 15 years and they meant so much to me."

MUSIC DETAILS:
- Opening: "Amazing Grace" performed by Riverside Gospel Choir (after Pastor's opening words)
- Closing music: "What a Wonderful World" sung by Sarah Rodriguez (niece) before final remarks

MARGARET'S DATES:
Born: June 15, 1952
Passed: January 18, 2025

Full name: Margaret Ellen Rodriguez
EOF

chown ga:ga "$NOTES_PATH"

echo "✅ Service notes created at: $NOTES_PATH"

# Create an optional reference template (agent doesn't have to use it)
TEMPLATE_PATH="$WORKSPACE_DIR/funeral_template_reference.docx"

cat > /tmp/create_template.py << 'PYEOF'
#!/usr/bin/env python3
from docx import Document
from docx.shared import Pt, Inches
from docx.enum.text import WD_ALIGN_PARAGRAPH
import sys

doc = Document()

# Set margins
sections = doc.sections
for section in sections:
    section.top_margin = Inches(1)
    section.bottom_margin = Inches(1)
    section.left_margin = Inches(1)
    section.right_margin = Inches(1)

# Template structure (with placeholders)
title = doc.add_paragraph('[SERVICE TITLE - e.g., Celebration of Life]')
title.alignment = WD_ALIGN_PARAGRAPH.CENTER
title.runs[0].bold = True
title.runs[0].font.size = Pt(16)

name = doc.add_paragraph('[DECEASED FULL NAME]')
name.alignment = WD_ALIGN_PARAGRAPH.CENTER
name.runs[0].bold = True
name.runs[0].font.size = Pt(16)

dates = doc.add_paragraph('[BIRTH DATE] - [DEATH DATE]')
dates.alignment = WD_ALIGN_PARAGRAPH.CENTER
dates.runs[0].font.size = Pt(14)

doc.add_paragraph()

service_info = doc.add_paragraph('[SERVICE DATE AND TIME]')
service_info.alignment = WD_ALIGN_PARAGRAPH.CENTER
service_info.runs[0].font.size = Pt(12)

location = doc.add_paragraph('[SERVICE LOCATION]')
location.alignment = WD_ALIGN_PARAGRAPH.CENTER
location.runs[0].font.size = Pt(12)

doc.add_paragraph()

order_heading = doc.add_paragraph('Order of Service')
order_heading.alignment = WD_ALIGN_PARAGRAPH.CENTER
order_heading.runs[0].bold = True
order_heading.runs[0].font.size = Pt(14)

doc.add_paragraph('[List speakers, readings, and music selections]')

doc.add_paragraph()
doc.add_paragraph('[Include any readings or poems]')
doc.add_paragraph()
doc.add_paragraph('[Reception details]')
doc.add_paragraph()
doc.add_paragraph('[Remote attendance information]')
doc.add_paragraph()
doc.add_paragraph('[Memorial donation information]')

doc.save(sys.argv[1])
PYEOF

chmod +x /tmp/create_template.py
python3 /tmp/create_template.py "$TEMPLATE_PATH"
chown ga:ga "$TEMPLATE_PATH"

echo "✅ Optional template reference created at: $TEMPLATE_PATH"

# Launch ONLYOFFICE with a blank document
echo "Launching ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors --new:word > /tmp/onlyoffice_memorial_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_memorial_task.log || true
fi

# Wait for window
if ! wait_for_window "ONLYOFFICE" 30; then
    echo "ERROR: ONLYOFFICE window did not appear"
fi

# Protect ONLYOFFICE from OOM killer
protect_onlyoffice_from_oom

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 960 540 click 1" || true
sleep 1

# Focus ONLYOFFICE window
focus_onlyoffice_window

echo "=== Memorial Service Program Task Setup Complete ==="
echo ""
echo "📝 TASK INSTRUCTIONS:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "SCENARIO: You are helping a grieving family member create a memorial"
echo "service program. Information is scattered across multiple texts and emails."
echo ""
echo "READ: $WORKSPACE_DIR/service_notes_fragments.txt"
echo "      This file contains all the fragmented information you need."
echo ""
echo "CREATE: $WORKSPACE_DIR/final_service_program.docx"
echo ""
echo "REQUIRED CONTENT (synthesize from fragments):"
echo "  1. Cover section (centered, bold, 16pt):"
echo "     - Service title (e.g., 'Celebration of Life')"
echo "     - Deceased name: Margaret Ellen Rodriguez"
echo "     - Dates: June 15, 1952 - January 18, 2025"
echo ""
echo "  2. Service information (centered, 12pt):"
echo "     - Date: Saturday, January 25, 2025"
echo "     - Time: 2:00 PM"
echo "     - Location: Riverside Community Chapel, 847 Oak Street"
echo ""
echo "  3. Order of Service (with all participants and music):"
echo "     - Opening Words - Pastor Michael Chen"
echo "     - Musical Selection: 'Amazing Grace' - Riverside Gospel Choir"
echo "     - Eulogy - David Rodriguez (son)"
echo "     - Readings - Jennifer Martinez (daughter), Emma Wilson (granddaughter)"
echo "     - Musical Selection: 'What a Wonderful World' - Sarah Rodriguez (niece)"
echo "     - Closing Remarks - Pastor Michael Chen"
echo ""
echo "  4. Include the poem 'Do Not Stand at My Grave and Weep'"
echo "     (properly formatted with line breaks, indented, italic)"
echo ""
echo "  5. Reception details:"
echo "     - Martinez Family Restaurant, 1240 River Road"
echo "     - Light refreshments, vegetarian options"
echo ""
echo "  6. Remote attendance information (Zoom link from fragments)"
echo ""
echo "  7. Memorial donations to Riverside Animal Shelter"
echo ""
echo "FORMAT: Use proper spacing, centered titles, professional appearance"
echo "        suitable for printing at a funeral service."
echo ""
echo "SAVE AS: $WORKSPACE_DIR/final_service_program.docx"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"