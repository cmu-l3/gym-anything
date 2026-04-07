#!/bin/bash
echo "=== Setting up executive_briefing_from_spec task ==="

source /workspace/scripts/task_utils.sh

# Kill any running WPS instance
kill_wps

# Reset the presentation file to original clean state
reset_presentation

# Remove any previous executive_briefing.pptx to ensure clean start
rm -f /home/ga/Documents/executive_briefing.pptx

# Write the executive briefing specification file
cat > /home/ga/Documents/executive_briefing_spec.txt << 'SPECEOF'
EXECUTIVE BRIEFING SPECIFICATION
=================================
Prepared for: Board of Directors
Subject: Infrastructure Performance Review Q4 2024
Prepared by: Operations Management Team
Date: 2024-12-01

REQUIRED OUTPUT FILE
--------------------
Save the final presentation to: /home/ga/Documents/executive_briefing.pptx

SLIDE REQUIREMENTS
------------------
1. MAXIMUM SLIDE COUNT: The briefing must contain NO MORE than 12 slides.
   Board members have limited time; a concise deck is essential.

2. FIRST SLIDE (Title Slide): The first slide MUST have the exact title:
   "Apache Infrastructure: Q4 2024 Executive Briefing"
   This title must match exactly (capitalization and punctuation matter).

3. LAST SLIDE (Closing): The last slide must contain the words "Q&A" or
   "Questions" in the title or body. This is the standard board meeting
   closing format.

4. THEME/DESIGN: Apply a professional, non-default theme. Do NOT use the
   default white background theme. The board expects polished visuals.
   Recommended: Apply a dark or blue professional theme from WPS's built-in
   designs (Design tab > Themes or Slide Design panel).

5. CONTENT FOCUS: Select the most strategically important slides from the
   original 48-slide deck. Focus on:
   - Key performance metrics and results
   - Capacity planning and scalability
   - Cost and efficiency highlights
   - Recommendations and next steps
   Do NOT include low-level technical configuration details — executives
   do not need to see raw server configuration parameters.

6. SEPARATE FILE: Save this briefing as a SEPARATE file. Do NOT overwrite
   the original performance.pptx. The original must remain intact.

FORMATTING GUIDELINES
---------------------
- Keep slide titles clear and businesslike
- Use bullet points, not paragraphs
- Limit each slide to 5 bullet points maximum
- Ensure all text is readable at boardroom projector size

DELIVERY CHECKLIST
------------------
[ ] File saved to /home/ga/Documents/executive_briefing.pptx
[ ] Slide 1 title: "Apache Infrastructure: Q4 2024 Executive Briefing"
[ ] Total slides: 12 or fewer
[ ] Last slide contains "Q&A" or "Questions"
[ ] Professional theme applied (not default white)
[ ] Original performance.pptx is unchanged
SPECEOF

chown ga:ga /home/ga/Documents/executive_briefing_spec.txt

# Record task start timestamp for anti-gaming
date +%s > /tmp/executive_briefing_from_spec_start_ts

# Launch WPS Presentation with the original file
launch_wps_with_file "/home/ga/Documents/presentations/performance.pptx"

# Wait for WPS to fully load
wait_for_wps 60

# Maximize the window
maximize_wps

sleep 2
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key ctrl+Home 2>/dev/null || true

# Take initial screenshot for evidence documentation
take_screenshot /tmp/executive_briefing_from_spec_start_screenshot.png

echo "=== executive_briefing_from_spec task setup complete ==="
echo "Spec file placed at: /home/ga/Documents/executive_briefing_spec.txt"
