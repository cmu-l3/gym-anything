#!/bin/bash
set -e
echo "=== Setting up Course Syllabus Formatting task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
su - ga -c "mkdir -p /home/ga/Documents"

# Clean up any previous task artifacts
rm -f /home/ga/Documents/ENVS4350_Draft.docx
rm -f /home/ga/Documents/ENVS4350_Syllabus_Final.docx

# Generate the realistic draft document using python-docx
echo "Creating draft document..."
su - ga -c 'python3 - << "PYEOF"
from docx import Document
from docx.shared import Pt
import os

doc = Document()

# Set Normal style defaults to simulate unformatted text
style = doc.styles["Normal"]
style.font.name = "Calibri"
style.font.size = Pt(11)

# Course Title (plain text, manually enlarged and bold, NOT Heading 1)
title_para = doc.add_paragraph()
title_run = title_para.add_run("ENVS 4350: Climate Change Science and Policy")
title_run.bold = True
title_run.font.size = Pt(16)

doc.add_paragraph("")

# Section: Course Information (manually bolded, Normal style)
info_header = doc.add_paragraph()
info_run = info_header.add_run("Course Information")
info_run.bold = True
info_run.font.size = Pt(13)

doc.add_paragraph("Instructor: Dr. Sarah Mitchell")
doc.add_paragraph("Office: Environmental Sciences Building, Room 312")
doc.add_paragraph("Email: s.mitchell@university.edu")
doc.add_paragraph("Meeting Time: Monday/Wednesday/Friday 10:00-10:50 AM")
doc.add_paragraph("Location: Clark Hall 205")
doc.add_paragraph("")

# Section: Course Description
desc_header = doc.add_paragraph()
desc_run = desc_header.add_run("Course Description")
desc_run.bold = True
desc_run.font.size = Pt(13)

doc.add_paragraph(
    "This course examines the scientific basis of climate change, its observed and "
    "projected impacts on natural and human systems, and the policy frameworks developed "
    "to address mitigation and adaptation. Students will critically evaluate primary "
    "literature from climate science, ecology, economics, and political science. The "
    "course integrates physical science fundamentals including radiative forcing, carbon "
    "cycle dynamics, and climate modeling with policy analysis."
)
doc.add_paragraph("")

# Section: Learning Objectives
obj_header = doc.add_paragraph()
obj_run = obj_header.add_run("Learning Objectives")
obj_run.bold = True
obj_run.font.size = Pt(13)

objectives = [
    "Explain the physical science basis of anthropogenic climate change.",
    "Interpret and critically evaluate climate model projections and uncertainties.",
    "Analyze observed climate change impacts using peer-reviewed literature.",
    "Evaluate mitigation strategies including carbon pricing and renewable energy.",
    "Assess the effectiveness of international climate agreements."
]
for i, obj in enumerate(objectives, 1):
    doc.add_paragraph(f"{i}. {obj}")
doc.add_paragraph("")

# Section: Course Schedule (Plain text lines instead of a table)
sched_header = doc.add_paragraph()
sched_run = sched_header.add_run("Course Schedule")
sched_run.bold = True
sched_run.font.size = Pt(13)

schedule_lines = [
    "Week 1 | Aug 26-30 | Intro to Climate System | Reading: IPCC AR6 WGI Chapter 1",
    "Week 2 | Sep 2-6 | Radiative Forcing | Reading: Pierrehumbert (2011)",
    "Week 3 | Sep 9-13 | Carbon Cycle | Reading: Friedlingstein et al. (2022)",
    "Week 4 | Sep 16-20 | Climate Models | Reading: IPCC AR6 WGI Chapter 4",
    "Week 5 | Sep 23-27 | Paleoclimate & Sensitivity | Reading: Sherwood et al. (2020)",
    "Week 6 | Sep 30-Oct 4 | Temperature Changes | Assignment: Draft due",
    "Week 7 | Oct 7-11 | Sea Level Rise | Reading: Bamber et al. (2019)",
    "Week 8 | Oct 14-18 | MIDTERM EXAM & Ecosystems | Midterm on Monday",
    "Week 9 | Oct 21-25 | Water Resources | Reading: Diffenbaugh et al. (2017)",
    "Week 10 | Oct 28-Nov 1 | Human Health | Reading: Watts et al. (2021)",
    "Week 11 | Nov 4-8 | Economics of Climate Change | Reading: Nordhaus (2019)",
    "Week 12 | Nov 11-15 | Carbon Pricing | Assignment: Policy brief due",
    "Week 13 | Nov 18-22 | International Policy | Reading: Falkner (2016)",
    "Week 14 | Nov 25-27 | Adaptation Strategies | Thanksgiving Break",
    "Week 15 | Dec 2-6 | Course Synthesis | Final Paper Due"
]
for line in schedule_lines:
    doc.add_paragraph(line)
doc.add_paragraph("")

# Section: Grading Policy (Paragraph text instead of a table)
grade_header = doc.add_paragraph()
grade_run = grade_header.add_run("Grading Policy")
grade_run.bold = True
grade_run.font.size = Pt(13)

doc.add_paragraph(
    "Your grade in this course will be determined by the following components. "
    "Class Participation accounts for 10% of your final grade. "
    "The Data Labs are worth 15% collectively and involve hands-on analysis. "
    "The Literature Review paper is worth 15% of your grade. "
    "The Midterm Exam counts for 20% and covers all material from Weeks 1-7. "
    "The Policy Brief assignment is worth 15% and requires analysis of a specific proposal. "
    "The Final Paper accounts for 25% of your total grade and is a comprehensive research paper."
)
doc.add_paragraph("")

# Section: Required Materials
mat_header = doc.add_paragraph()
mat_run = mat_header.add_run("Required Materials")
mat_run.bold = True
mat_run.font.size = Pt(13)

doc.add_paragraph("Dessler, A. (2022). Introduction to Modern Climate Change. Cambridge UP.")
doc.add_paragraph("")

# Section: Course Policies (Missing Academic Integrity & Accommodation)
pol_header = doc.add_paragraph()
pol_run = pol_header.add_run("Course Policies")
pol_run.bold = True
pol_run.font.size = Pt(13)

att_sub = doc.add_paragraph()
att_run = att_sub.add_run("Attendance Policy")
att_run.bold = True
doc.add_paragraph(
    "Regular attendance is expected. More than three unexcused absences will result "
    "in a reduction of your participation grade."
)

# Document deliberately lacks the 2 required institutional policy sections

output_path = "/home/ga/Documents/ENVS4350_Draft.docx"
doc.save(output_path)
PYEOF
'

# Verify draft was created
if [ ! -f /home/ga/Documents/ENVS4350_Draft.docx ]; then
    echo "ERROR: Failed to create draft document"
    exit 1
fi

# Record initial file states
md5sum /home/ga/Documents/ENVS4350_Draft.docx > /tmp/draft_checksum.txt

# Kill any existing WPS processes
pkill -f wps 2>/dev/null || true
pkill -f wpp 2>/dev/null || true
sleep 2

# Launch WPS Writer with the draft document
echo "Launching WPS Writer..."
su - ga -c "DISPLAY=:1 wps /home/ga/Documents/ENVS4350_Draft.docx &"
sleep 5

# Dismiss EULA and first-run dialogs
dismiss_wps_dialogs || true
sleep 2

# Wait for WPS Writer window
wait_for_window "ENVS4350\|WPS Writer" 30 || true

# Maximize and focus the WPS Writer window
WPS_WIN=$(DISPLAY=:1 wmctrl -l | grep -i "ENVS4350\|WPS Writer" | head -1 | awk '{print $1}')
if [ -n "$WPS_WIN" ]; then
    DISPLAY=:1 wmctrl -ir "$WPS_WIN" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -ia "$WPS_WIN" 2>/dev/null || true
    echo "WPS Writer window maximized and focused"
fi

sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Course Syllabus Formatting task setup complete ==="