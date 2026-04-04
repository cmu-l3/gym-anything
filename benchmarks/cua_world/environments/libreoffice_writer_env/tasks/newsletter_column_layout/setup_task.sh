#!/bin/bash
set -e
echo "=== Setting up Newsletter Column Layout Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Clean up previous run artifacts
rm -f /home/ga/Documents/diabetes_newsletter.docx
rm -f /home/ga/Documents/diabetes_newsletter_draft.docx

# 3. Create the draft document with realistic content
# We use python-docx to generate a clean "messy" state (plain text, no formatting)
python3 << 'PYEOF'
from docx import Document
from docx.shared import Pt

doc = Document()

# Set default font to something generic to ensure agent has to apply styles
style = doc.styles['Normal']
font = style.font
font.name = 'Liberation Serif'
font.size = Pt(11)

# Newsletter Content
content = [
    "Harmony Health Quarterly",
    "Your Guide to Living Well with Type 2 Diabetes — Spring 2024",
    "",
    "Understanding Your Blood Sugar Numbers",
    "Managing Type 2 diabetes starts with understanding what your blood sugar numbers mean. The American Diabetes Association recommends the following targets for most adults with diabetes: before meals (fasting) 80–130 mg/dL, two hours after starting a meal less than 180 mg/dL, and A1C (3-month average) less than 7 percent.",
    "Your A1C test, which your provider orders every three to six months, gives you a picture of your average blood sugar over the past two to three months. Each percentage point drop in A1C reduces the risk of microvascular complications—eye disease, kidney disease, and nerve damage—by approximately 40 percent.",
    "Keep a log of your daily readings. Patterns in your numbers help your care team adjust your treatment plan. If you see readings consistently above 180 mg/dL after meals or below 70 mg/dL at any time, contact your provider promptly.",
    "",
    "Heart-Healthy Eating on a Budget",
    "Living with diabetes does not mean eating expensive specialty foods. The Diabetes Plate Method, endorsed by the American Diabetes Association, is a simple way to build balanced meals using affordable ingredients.",
    "Fill half your plate with non-starchy vegetables such as broccoli, spinach, green beans, or carrots. These are among the least expensive items in the produce section, especially when purchased frozen.",
    "Fill one quarter of your plate with lean protein. Budget-friendly options include canned tuna, eggs, dried beans and lentils, and chicken thighs. Dried beans and lentils are particularly economical—one pound of dried black beans costs approximately two dollars and yields six servings of high-fiber, high-protein food.",
    "Fill one quarter of your plate with carbohydrate foods such as brown rice, whole wheat bread, or sweet potatoes. Choosing whole grains over refined grains slows the rate at which sugar enters your bloodstream.",
    "",
    "Small changes today lead to lasting health improvements tomorrow. You do not have to overhaul your entire life at once—pick one goal this week and build from there.",
    "",
    "Staying Active: Exercise Tips for Every Ability Level",
    "The Centers for Disease Control and Prevention recommends that adults with Type 2 diabetes aim for at least 150 minutes of moderate-intensity aerobic activity per week. Regular physical activity improves insulin sensitivity, lowers blood sugar, reduces cardiovascular risk, and supports mental health.",
    "If you are new to exercise, start with 10-minute walks after meals. Post-meal walking has been shown in research to be more effective at lowering blood sugar than a single 30-minute walk at another time of day.",
    "For those with mobility limitations, chair-based exercises can be equally effective. Seated leg lifts, arm circles, resistance band exercises, and seated marching all raise heart rate and engage muscles without requiring standing balance.",
    "",
    "Know Your Medications",
    "Many people with Type 2 diabetes take one or more medications to help control blood sugar. Understanding what each medication does can help you take them correctly and recognize side effects early.",
    "Metformin is the most commonly prescribed first-line medication. It works by reducing the amount of glucose your liver produces and by improving your body's sensitivity to insulin. Common side effects include stomach upset and diarrhea, which usually improve after a few weeks.",
    "SGLT2 inhibitors work by helping your kidneys remove excess sugar through urine. GLP-1 receptor agonists are injectable medications that help the pancreas release insulin in response to meals, slow digestion, and reduce appetite.",
    "Never stop or change the dose of your medication without talking to your provider first.",
    "",
    "Harmony Community Health Center, 1250 Wellness Drive, Suite 300, Springfield, IL 62704. Phone: (555) 234-5678. Website: www.harmonychc.org. Diabetes Education Classes: Every Tuesday and Thursday, 2:00–3:30 PM."
]

for paragraph in content:
    doc.add_paragraph(paragraph)

# Remove the empty first paragraph docx sometimes creates
if len(doc.paragraphs) > 0 and not doc.paragraphs[0].text.strip():
    p = doc.paragraphs[0]._element
    p.getparent().remove(p)

doc.save('/home/ga/Documents/diabetes_newsletter_draft.docx')
PYEOF

# Ensure permissions
chown ga:ga /home/ga/Documents/diabetes_newsletter_draft.docx

# 4. Launch LibreOffice Writer with the draft
echo "Launching LibreOffice Writer..."
su - ga -c "DISPLAY=:1 libreoffice --writer /home/ga/Documents/diabetes_newsletter_draft.docx > /dev/null 2>&1 &"

# 5. Wait for window
wait_for_window "LibreOffice Writer" 30 || wait_for_window "diabetes_newsletter" 30

# 6. Maximize and focus (Critical for VLM/Agent)
# We use a slight delay to ensure the window manager has registered the window
sleep 2
WID=$(get_writer_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz
    focus_window "$WID"
fi

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="