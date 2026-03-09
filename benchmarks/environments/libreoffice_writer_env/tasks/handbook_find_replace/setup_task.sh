#!/bin/bash
set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Handbook Find & Replace Task ==="

# 1. Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# 2. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt
chmod 644 /tmp/task_start_time.txt

# 3. Generate the source document with specific errors
# We use python3 to generate a DOCX with controlled errors
python3 << 'PYEOF'
from docx import Document
from docx.shared import Pt
from docx.enum.text import WD_ALIGN_PARAGRAPH

doc = Document()

# Title
head = doc.add_heading('Greenfield Industries Employee Handbook', 0)
head.alignment = WD_ALIGN_PARAGRAPH.CENTER

# Section 1: Welcome (Error: "Greenfield industries", "2019")
doc.add_heading('1. Welcome', level=1)
p = doc.add_paragraph(
    "Welcome to Greenfield industries!  We are delighted that you have chosen to join our team.  "
    "This handbook is designed to acquaint you with Greenfield Industries and provide you with "
    "information about working conditions, employee benefits, and some of the policies affecting "
    "your employment.  This version is effective as of January 1, 2019."
)

# Section 2: Employment (Error: "dept.", double spaces)
doc.add_heading('2. Employment Policies', level=1)
doc.add_paragraph("2.1 Equal Opportunity Employment")
p = doc.add_paragraph(
    "Greenfield industries provides equal employment opportunities to all employees and applicants.  "
    "If you have questions about this policy, please contact the HR dept. immediately."
)

doc.add_paragraph("2.2 Attendance")
p = doc.add_paragraph(
    "Punctuality and regular attendance are essential to the successful operation of the "
    "Production Dept.  If you are unable to report for work, you must notify your supervisor "
    "before the start of your shift."
)

# Section 3: Communications (Error: email domain, "dept.")
doc.add_heading('3. Electronic Communications', level=1)
p = doc.add_paragraph(
    "Employees are provided with company email accounts for business use.  "
    "Examples of appropriate addresses include support@greenfield-ind.com or "
    "sales@greenfield-ind.com.  Please do not use your address for personal subscriptions."
)
p = doc.add_paragraph(
    "The IT Dept. monitors all network traffic.  Any suspicious activity should be reported to "
    "security@greenfield-ind.com immediately."
)

# Section 4: Benefits (Error: "2019")
doc.add_heading('4. Benefits', level=1)
p = doc.add_paragraph(
    "Eligible employees are entitled to benefits as outlined in the 2019 Benefits Guide.  "
    "Vacation requests must be submitted to the Admin dept. at least two weeks in advance."
)

# Section 5: Safety (Error: "Greenfield industries", double spaces)
doc.add_heading('5. Safety', level=1)
p = doc.add_paragraph(
    "At Greenfield industries, safety is our top priority.  All accidents must be reported "
    "to the Safety Manager at safety@greenfield-ind.com within 24 hours.  Failure to report "
    "incidents is grounds for disciplinary action."
)

# Section 6: Acknowledgement (Error: "2019", "Greenfield industries")
doc.add_heading('6. Acknowledgement', level=1)
p = doc.add_paragraph(
    "I acknowledge that I have received the 2019 Employee Handbook.  I understand that "
    "Greenfield industries may revise these policies at any time.  I agree to read and comply "
    "with the policies contained herein."
)
p = doc.add_paragraph(
    "Signed: __________________________  Date: __________________________"
)

# Footer contact
p = doc.add_paragraph("Questions? Contact Human Resources at hr@greenfield-ind.com")
p.alignment = WD_ALIGN_PARAGRAPH.CENTER

doc.save("/home/ga/Documents/employee_handbook.docx")
print("Generated handbook with intentional errors.")
PYEOF

# Ensure permissions
chown ga:ga /home/ga/Documents/employee_handbook.docx
chmod 666 /home/ga/Documents/employee_handbook.docx

# 4. Launch LibreOffice Writer
echo "Launching LibreOffice Writer..."
su - ga -c "DISPLAY=:1 libreoffice --writer --norestore /home/ga/Documents/employee_handbook.docx > /tmp/writer.log 2>&1 &"

# 5. Wait for window and maximize
wait_for_window "LibreOffice Writer" 60
sleep 2

# Get Window ID
WID=$(get_writer_window_id)
if [ -n "$WID" ]; then
    echo "Maximizing window $WID..."
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz
fi

# 6. Take initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="