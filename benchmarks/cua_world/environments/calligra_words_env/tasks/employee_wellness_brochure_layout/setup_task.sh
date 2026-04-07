#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Employee Wellness Brochure Layout Task ==="

install -d -o ga -g ga /home/ga/Documents
install -d -o ga -g ga /home/ga/Desktop
kill_calligra_processes

# Create a sample logo image using base64 to ensure no dependencies fail
cat << 'EOF' > /tmp/logo.b64
iVBORw0KGgoAAAANSUhEUgAAAGQAAABkAQMAAABKLAcXAAAABlBMVEX/AAB04+QAAAAAJUlEQVR42u3AIQEAAACCIP+vbxfEAAAAAAAAAAAAAAAAAAAAwA4uYAABE1YlCQAAAABJRU5ErkJggg==
EOF
base64 -d /tmp/logo.b64 > /home/ga/Desktop/wellness_logo.png
chown ga:ga /home/ga/Desktop/wellness_logo.png

rm -f /home/ga/Documents/wellness_brochure_draft.odt

# Create the unformatted text document using odfpy
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.text import P

doc = OpenDocumentText()

def add_paragraph(text=""):
    doc.text.addElement(P(text=text))

add_paragraph("Meridian Corp Wellness Program")
add_paragraph("Invest in Your Health, Invest in Your Future")
add_paragraph("")
add_paragraph("Program Overview")
add_paragraph("Meridian Corp is committed to the physical, mental, and emotional well-being of our employees. Our new comprehensive wellness program is designed to provide you with the resources, support, and incentives you need to live a healthier life both inside and outside the workplace. Whether your goal is to reduce stress, improve your fitness, or manage a chronic condition, this program offers personalized pathways to success.")
add_paragraph("")
add_paragraph("Eligibility")
add_paragraph("All full-time and part-time employees who have been with Meridian Corp for at least 30 days are eligible to participate. Dependents enrolled in the company health insurance plan also have access to select services. Participation is entirely voluntary and all personal health information is kept strictly confidential in compliance with HIPAA regulations.")
add_paragraph("")
add_paragraph("Covered Services")
add_paragraph("The wellness program provides access to a wide array of free or heavily subsidized services. These offerings are designed to address multiple dimensions of wellness:")
add_paragraph("Health screenings")
add_paragraph("Mental health counseling")
add_paragraph("Gym membership subsidies")
add_paragraph("Nutrition planning")
add_paragraph("")
add_paragraph("Fitness Incentives")
add_paragraph("We believe that healthy habits should be rewarded. By participating in eligible activities, employees can earn points that translate into real financial rewards. Logging 150 minutes of moderate exercise per week, attending virtual wellness seminars, or participating in the annual step challenge will earn points. Accrued points can be redeemed for health insurance premium discounts, extra PTO hours, or contributions to your Health Savings Account (HSA).")
add_paragraph("")
add_paragraph("How to Enroll")
add_paragraph("Enrolling in the wellness program is quick and easy. Log in to the Meridian HR Portal, navigate to the 'Benefits' tab, and click on 'Wellness Program Registration'. You will be prompted to complete a brief, confidential health risk assessment which will help tailor the program recommendations to your specific needs. Enrollment remains open year-round, but early registrants receive a bonus incentive. For any questions, please contact the HR Benefits Team at wellness@meridiancorp.com.")

doc.save("/home/ga/Documents/wellness_brochure_draft.odt")
PYEOF

chown ga:ga /home/ga/Documents/wellness_brochure_draft.odt

# Record task start time and file mtime
date +%s > /tmp/task_start_time.txt
stat -c %Y /home/ga/Documents/wellness_brochure_draft.odt > /tmp/initial_mtime.txt 2>/dev/null || echo "0" > /tmp/initial_mtime.txt

# Launch Calligra Words
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority calligrawords /home/ga/Documents/wellness_brochure_draft.odt >/dev/null 2>&1 &"

# Wait for window
wait_for_window "wellness_brochure_draft" 30

# Maximize window
WID=$(get_calligra_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    # Dismiss any dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png ga

echo "=== Task Setup Complete ==="