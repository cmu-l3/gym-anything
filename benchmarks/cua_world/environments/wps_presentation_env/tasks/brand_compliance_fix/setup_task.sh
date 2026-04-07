#!/bin/bash
echo "=== Setting up brand_compliance_fix task ==="

source /workspace/scripts/task_utils.sh

# Kill any running WPS instance
kill_wps

# Reset the presentation file to original clean state
reset_presentation

# Remove any previous branded file
rm -f /home/ga/Documents/branded_cloudserver.pptx

# Install python-pptx for error injection
pip3 install python-pptx lxml 2>/dev/null || true

# Ensure Desktop exists
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop 2>/dev/null || true

# Write the brand guidelines spec file
cat > /home/ga/Desktop/brand_guidelines.txt << 'GUIDEEOF'
CLOUDSERVER PRO — BRAND COMPLIANCE GUIDELINES
==============================================
Document version: 2024-Q4
Prepared by: Brand & Marketing Team

PURPOSE
-------
All client-facing presentations must comply with CloudServer Pro brand
standards before distribution. Non-compliant presentations must be corrected
before any client meeting.

REQUIREMENT 1 — TITLE SLIDE
-----------------------------
The first slide of every client presentation MUST have EXACTLY this title:
  "CloudServer Pro: Performance Benchmarking Solutions"
(Note: exact capitalization and punctuation are required.)

REQUIREMENT 2 — CLOSING SLIDE
-------------------------------
The LAST slide of the presentation must be a "Contact Us" slide. The slide
must contain ALL of the following contact information:
  - Slide title: "Contact Us"
  - Email address: sales@cloudserverpro.com
  - Phone number: 1-800-CLOUD-PRO

If the last slide already exists with some content, REPLACE it with a new
"Contact Us" slide containing the required information.

REQUIREMENT 3 — NO ALL CAPS TITLES
------------------------------------
CloudServer Pro brand guidelines prohibit ALL CAPS slide titles. Any slide
with a title where EVERY LETTER is uppercase (e.g., "PERFORMANCE ANALYSIS",
"KEY METRICS") must have its title changed to Title Case.
Exception: Acronyms of 3 letters or fewer may remain uppercase.

REQUIREMENT 4 — SAVE LOCATION
-------------------------------
Save the compliant presentation as a NEW FILE to:
  /home/ga/Documents/branded_cloudserver.pptx
Do NOT overwrite the original performance.pptx file.

COMPLIANCE CHECKLIST
--------------------
[ ] Slide 1 title: "CloudServer Pro: Performance Benchmarking Solutions"
[ ] Last slide title: "Contact Us"
[ ] Last slide body contains: sales@cloudserverpro.com
[ ] Last slide body contains: 1-800-CLOUD-PRO
[ ] No ALL CAPS slide titles remain
[ ] File saved to: /home/ga/Documents/branded_cloudserver.pptx
GUIDEEOF

chown ga:ga /home/ga/Desktop/brand_guidelines.txt

# Inject brand violations into the presentation:
# 1. Change slide 1 title to wrong/lowercase text
# 2. Change slides 5, 9, 14, 20 (0-indexed: 4, 8, 13, 19) titles to ALL CAPS
python3 << 'PYEOF'
from pptx import Presentation

PPTX_PATH = '/home/ga/Documents/presentations/performance.pptx'

# Slides to make ALL CAPS (0-indexed)
ALL_CAPS_INDICES = [4, 8, 13, 19]

prs = Presentation(PPTX_PATH)
total = len(prs.slides)
print(f"Total slides: {total}")

def get_title_shape(slide):
    for shape in slide.shapes:
        if hasattr(shape, 'placeholder_format') and shape.placeholder_format is not None:
            if shape.placeholder_format.idx == 0:
                return shape
    return None

# Error 1: Change slide 1 title to wrong branded text (lowercase, wrong product name)
slide0 = prs.slides[0]
title_shape = get_title_shape(slide0)
if title_shape and title_shape.has_text_frame:
    tf = title_shape.text_frame
    original = tf.paragraphs[0].text if tf.paragraphs else ""
    for para in tf.paragraphs:
        for run in para.runs:
            run.text = 'apache http server performance analysis report 2024'
            break
        break
# Error 2: Change specified slides to ALL CAPS titles
for idx in ALL_CAPS_INDICES:
    if idx < total:
        slide = prs.slides[idx]
        title_shape = get_title_shape(slide)
        if title_shape and title_shape.has_text_frame:
            tf = title_shape.text_frame
            original = tf.paragraphs[0].text if tf.paragraphs else ""
            new_title = original.upper()
            for para in tf.paragraphs:
                for run in para.runs:
                    run.text = new_title
                    break
                break

prs.save(PPTX_PATH)
print("Setup complete.")
PYEOF

# Record task start timestamp for anti-gaming
date +%s > /tmp/brand_compliance_fix_start_ts

# Launch WPS Presentation with the modified file
launch_wps_with_file "/home/ga/Documents/presentations/performance.pptx"

# Wait for WPS to fully load
wait_for_wps 60

# Maximize the window
maximize_wps

sleep 2
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key ctrl+Home 2>/dev/null || true

# Take initial screenshot for evidence documentation
take_screenshot /tmp/brand_compliance_fix_start_screenshot.png

echo "=== brand_compliance_fix task setup complete ==="
