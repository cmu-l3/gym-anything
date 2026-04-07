#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Patient Education Brochure Layout Task ==="

install -d -o ga -g ga /home/ga/Documents
install -d -o ga -g ga /home/ga/Desktop
kill_calligra_processes

# Create the print shop specification file
cat > /home/ga/Desktop/print_shop_specs.txt << 'EOF'
HOSPITAL PRINT SHOP - BROCHURE SPECIFICATIONS

To ensure the patient education guide prints correctly on our tri-fold machines, you MUST format the document exactly as follows:

PAGE LAYOUT:
- Orientation: Landscape
- Margins: 0.5 inches on all sides (Top, Bottom, Left, Right)
- Columns: 3 columns

TYPOGRAPHY & STRUCTURE:
- Title: "Living with Heart Failure: Patient Guide" must be Centered, Bold, and at least 18pt font.
- Headings: Apply the "Heading 1" style to the 5 main section titles.
- Lists: Convert the "Dietary Guidelines" (the items starting with asterisks) into a proper bulleted list.
- Table: Convert the "Daily Weight Log" section into a 3-column, 8-row table (Headers: Day, Weight, Symptoms; plus 7 empty rows for the patient to write in).
- Disclaimer: The "Medical Disclaimer" paragraph at the bottom must be Italicized.

DELIVERY:
- Save the finished document as: /home/ga/Documents/heart_failure_brochure_print.odt
EOF
chown ga:ga /home/ga/Desktop/print_shop_specs.txt

# Create the unformatted ODT file
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.text import P

doc = OpenDocumentText()

def add_p(text=""):
    doc.text.addElement(P(text=text))

add_p("Living with Heart Failure: Patient Guide")
add_p("")
add_p("Introduction")
add_p("Heart failure means your heart isn't pumping as well as it should. Your body depends on the heart's pumping action to deliver oxygen- and nutrient-rich blood to the body's cells. When the cells are nourished properly, the body can function normally. With heart failure, the weakened heart can't supply the cells with enough blood. This results in fatigue and shortness of breath.")
add_p("")
add_p("Symptoms to Watch For")
add_p("Contact your doctor immediately if you experience any of the following symptoms: sudden weight gain (more than 2-3 pounds in a day or 5 pounds in a week), shortness of breath while resting or lying flat, swelling in your ankles, legs, or abdomen, or increased fatigue and weakness.")
add_p("")
add_p("Dietary Guidelines")
add_p("* Limit your sodium (salt) intake to less than 2,000 mg per day.")
add_p("* Read nutrition labels carefully to check for hidden sodium.")
add_p("* Avoid processed meats, canned soups, and fast food.")
add_p("* Eat plenty of fresh fruits, vegetables, and whole grains.")
add_p("")
add_p("Fluid Management")
add_p("Because your heart is not pumping effectively, your body may retain fluid. Your doctor may restrict your daily fluid intake. Make sure to track all liquids, including water, coffee, juice, soup, and foods that melt like ice cream or gelatin.")
add_p("")
add_p("Daily Weight Log")
add_p("Day | Weight | Symptoms")
add_p("Day 1: ___")
add_p("Day 2: ___")
add_p("Day 3: ___")
add_p("Day 4: ___")
add_p("Day 5: ___")
add_p("Day 6: ___")
add_p("Day 7: ___")
add_p("")
add_p("Medical Disclaimer: This guide is for educational purposes only and is not intended to replace the advice of your doctor or healthcare provider. Always consult your medical team for diagnosis and treatment of your specific condition.")

doc.save("/home/ga/Documents/heart_failure_guide.odt")
PYEOF

chown ga:ga /home/ga/Documents/heart_failure_guide.odt

# Record task start time
date +%s > /tmp/task_start_time.txt

# Start Calligra Words
launch_calligra_document "/home/ga/Documents/heart_failure_guide.odt"
wait_for_window "Calligra Words" 30

# Maximize the window
wid=$(get_calligra_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    DISPLAY=:1 wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png ga

echo "=== Setup Complete ==="