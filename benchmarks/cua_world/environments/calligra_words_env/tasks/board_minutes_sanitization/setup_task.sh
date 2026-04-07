#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Board Minutes Sanitization Task ==="

install -d -o ga -g ga /home/ga/Documents
install -d -o ga -g ga /home/ga/Desktop
kill_calligra_processes
rm -f /home/ga/Documents/board_minutes_q4.odt

# ── Create the board minutes document with odfpy ──
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.style import Style, TextProperties, ParagraphProperties
from odf.text import P, H, Span

doc = OpenDocumentText()

# ── Define styles ──

# Heading 1 style (bold, 16pt)
h1_style = Style(name="Heading1", family="paragraph")
h1_style.addElement(TextProperties(attributes={
    "fontsize": "16pt",
    "fontweight": "bold",
    "fontsizecomplex": "16pt",
    "fontweightcomplex": "bold",
    "fontsizeasian": "16pt",
    "fontweightasian": "bold",
}))
h1_style.addElement(ParagraphProperties(attributes={
    "margintop": "0.4cm",
    "marginbottom": "0.2cm",
}))
doc.styles.addElement(h1_style)

# Title style (bold, 18pt, centered)
title_style = Style(name="Title", family="paragraph")
title_style.addElement(TextProperties(attributes={
    "fontsize": "18pt",
    "fontweight": "bold",
    "fontsizecomplex": "18pt",
    "fontweightcomplex": "bold",
    "fontsizeasian": "18pt",
    "fontweightasian": "bold",
}))
title_style.addElement(ParagraphProperties(attributes={
    "textalign": "center",
}))
doc.styles.addElement(title_style)

# Subtitle style (14pt, centered)
subtitle_style = Style(name="Subtitle", family="paragraph")
subtitle_style.addElement(TextProperties(attributes={
    "fontsize": "14pt",
    "fontsizecomplex": "14pt",
    "fontsizeasian": "14pt",
}))
subtitle_style.addElement(ParagraphProperties(attributes={
    "textalign": "center",
}))
doc.styles.addElement(subtitle_style)

# Body style (12pt, justified)
body_style = Style(name="BodyText", family="paragraph")
body_style.addElement(TextProperties(attributes={
    "fontsize": "12pt",
    "fontsizecomplex": "12pt",
    "fontsizeasian": "12pt",
}))
body_style.addElement(ParagraphProperties(attributes={
    "textalign": "justify",
    "marginbottom": "0.2cm",
}))
doc.styles.addElement(body_style)

# Bold span style for inline emphasis
bold_style = Style(name="BoldSpan", family="text")
bold_style.addElement(TextProperties(attributes={
    "fontweight": "bold",
    "fontweightcomplex": "bold",
    "fontweightasian": "bold",
}))
doc.styles.addElement(bold_style)

# Centered plain style (for metadata lines)
center_style = Style(name="CenterText", family="paragraph")
center_style.addElement(TextProperties(attributes={
    "fontsize": "12pt",
    "fontsizecomplex": "12pt",
    "fontsizeasian": "12pt",
}))
center_style.addElement(ParagraphProperties(attributes={
    "textalign": "center",
}))
doc.styles.addElement(center_style)


def add_title(text):
    p = P(stylename=title_style, text=text)
    doc.text.addElement(p)


def add_subtitle(text):
    p = P(stylename=subtitle_style, text=text)
    doc.text.addElement(p)


def add_center(text):
    p = P(stylename=center_style, text=text)
    doc.text.addElement(p)


def add_heading(text):
    h = H(outlinelevel=1, stylename=h1_style, text=text)
    doc.text.addElement(h)


def add_body(text):
    p = P(stylename=body_style, text=text)
    doc.text.addElement(p)


def add_blank():
    p = P(stylename=body_style, text="")
    doc.text.addElement(p)


# ── Document content ──

add_title("MERIDIAN TECHNOLOGIES INC.")
add_subtitle("Minutes of the Board of Directors Meeting")
add_center("Q4 2025 — December 18, 2025")
add_center("Conference Room A, Corporate Headquarters, San Jose, CA")
add_blank()
add_body(
    "Directors Present: Robert Chen (Chairman), Sarah Mitchell, "
    "David Okafor, Patricia Reeves, James Thornton, Lisa Yamamoto"
)
add_body(
    "Also Present: Michael Torres (CEO), Sarah Chen (General Counsel), "
    "Jennifer Walsh (CFO), Thomas Rivera (CHRO)"
)
add_blank()

# ── Call to Order ──
add_heading("Call to Order")
add_body(
    "Chairman Robert Chen called the meeting to order at 9:00 AM PST. "
    "A quorum was confirmed with all six directors present."
)
add_blank()

# ── Approval of Previous Minutes ──
add_heading("Approval of Previous Minutes")
add_body(
    "Director Mitchell moved to approve the minutes of the Q3 2025 meeting. "
    "Director Okafor seconded. The motion carried unanimously."
)
add_blank()

# ── Financial Report ──
add_heading("Financial Report")
add_body(
    "CFO Jennifer Walsh presented the Q4 financial results. The company reported "
    "revenue of $389 million for Q4, representing 12% year-over-year growth. "
    "Operating income was $67 million with an operating margin of 17.2%."
)
add_body(
    "The Board approved the 2026 capital expenditure budget of $200 million, "
    "focused on data center expansion and new product development facilities."
)
add_body(
    "The Board declared a quarterly dividend of $0.35 per share, payable on "
    "February 15, 2026, to shareholders of record as of January 31, 2026."
)
# CONTAMINATED: Non-public financial projection
add_body(
    "Walsh also shared preliminary Q4 revenue of $412 million based on unaudited "
    "projections including anticipated contract closes that were still under "
    "negotiation. This figure has not been publicly disclosed and differs from "
    "the final audited number."
)
add_blank()

# ── Strategic Initiatives ──
add_heading("Strategic Initiatives")
add_body(
    "CEO Torres provided an update on the company's strategic initiatives."
)
add_body(
    "The Advanced Analytics Platform continues to exceed adoption targets with "
    "340 enterprise customers onboarded in Q4."
)
# CONTAMINATED: Internal code name (first occurrence)
add_body(
    "Torres referred to the initiative internally as 'Project Falcon' and noted "
    "that the Project Falcon team has been expanded to 85 engineers."
)
add_body(
    "The Board discussed the company's cloud migration strategy and approved "
    "$45 million in infrastructure investments for FY2026."
)
# CONTAMINATED: Acquisition target and terms
add_body(
    "The Board discussed the potential acquisition of CloudNest Systems, a "
    "cloud-native infrastructure startup based in Seattle, for approximately "
    "$78 million acquisition price. Due diligence is expected to conclude by "
    "February 2026."
)
add_body(
    "The Board approved cybersecurity improvements including a new Security "
    "Operations Center and enhanced threat intelligence capabilities."
)
# CONTAMINATED: Internal code name (second occurrence)
add_body(
    "Director Thornton asked about the timeline for Project Falcon phase two "
    "rollout, and Torres confirmed that the Project Falcon roadmap targets "
    "general availability in Q2 2026."
)
add_blank()

# ── Legal and Compliance Update ──
add_heading("Legal and Compliance Update")
add_body(
    "General Counsel Sarah Chen provided the quarterly legal and compliance update."
)
add_body(
    "The company successfully resolved the Henderson patent dispute through "
    "mediation, with no material financial impact."
)
# CONTAMINATED: Attorney-client privileged material
add_body(
    "Chen advised that the pending Zhao v. Meridian patent infringement litigation "
    "has a 60% probability of adverse outcome based on recent case law developments. "
    "She recommended settling for $4.2 million to avoid the risk of a $15 million "
    "jury verdict. The Board discussed litigation strategy in detail."
)
add_body(
    "Chen confirmed that the company is in full compliance with all SEC reporting "
    "requirements and Sarbanes-Oxley internal controls."
)
add_body(
    "The company's annual audit by Ernst & Young is scheduled to commence in "
    "January 2026."
)
add_blank()

# ── Human Resources and Compensation ──
add_heading("Human Resources and Compensation")
add_body(
    "CHRO Thomas Rivera presented the annual talent review and retention update."
)
add_body(
    "The Board approved the appointment of Dr. James Park as Chief Technology "
    "Officer, effective January 15, 2026."
)
# CONTAMINATED: Individual executive compensation
add_body(
    "The Board approved CEO Torres's compensation package for 2026: base salary "
    "of $875,000, annual bonus of $1.2 million at target performance, and an "
    "RSU grant of 50,000 shares vesting over four years."
)
add_body(
    "Rivera reported that employee retention rates improved to 92% in Q4, up "
    "from 88% in Q3."
)
add_body(
    "The Board approved a company-wide 3.5% merit increase pool for 2026."
)
add_blank()

# ── New Business ──
add_heading("New Business")
add_body(
    "The Board discussed the schedule for the 2026 Annual Meeting of Shareholders, "
    "tentatively set for May 14, 2026."
)
add_body(
    "Director Reeves proposed forming an AI Ethics Advisory Committee. The Board "
    "agreed to discuss the proposal at the Q1 2026 meeting."
)
add_blank()

# ── Adjournment ──
add_heading("Adjournment")
add_body(
    "There being no further business, Chairman Chen adjourned the meeting at "
    "3:45 PM PST."
)
add_blank()
add_body("Respectfully submitted,")
add_body("Corporate Secretary")
add_body("Meridian Technologies Inc.")

doc.save("/home/ga/Documents/board_minutes_q4.odt", False)
print("Created board_minutes_q4.odt")
PYEOF

chown ga:ga /home/ga/Documents/board_minutes_q4.odt
chmod 0664 /home/ga/Documents/board_minutes_q4.odt

# ── Create sanitization policy ──
cat > /home/ga/Desktop/sanitization_policy.txt << 'POLICYEOF'
MERIDIAN TECHNOLOGIES INC.
Board Minutes Sanitization Policy — Public Filing Version

Before board minutes are filed with the SEC or distributed to shareholders, the following categories of sensitive information MUST be removed or redacted:

1. ATTORNEY-CLIENT PRIVILEGED COMMUNICATIONS
   Any discussion of pending litigation strategy, settlement recommendations,
   probability assessments of legal outcomes, or detailed legal advice from
   counsel must be removed entirely. Retain only the fact that a legal update
   was provided and any publicly-disclosed resolutions.

2. ACQUISITION TARGETS AND TERMS
   Names of specific acquisition targets, proposed purchase prices, and
   deal terms must be replaced with [REDACTED] until publicly announced.
   Retain the general fact that strategic opportunities were discussed.

3. INDIVIDUAL EXECUTIVE COMPENSATION
   Specific compensation figures (base salary, bonus amounts, equity grants)
   for named executives must be removed. These are disclosed separately
   in the proxy statement. Retain general compensation policy decisions
   (e.g., merit increase pools, new appointments).

4. NON-PUBLIC FINANCIAL PROJECTIONS
   Preliminary, unaudited, or forward-looking financial figures that differ
   from publicly reported numbers must be removed. Retain only the final
   audited/reported figures.

5. INTERNAL CODE NAMES
   Replace all internal project code names with their publicly announced
   names. The current mapping:
   - "Project Falcon" → "Advanced Analytics Platform"
POLICYEOF

chown ga:ga /home/ga/Desktop/sanitization_policy.txt
chmod 0644 /home/ga/Desktop/sanitization_policy.txt

echo "Launching Calligra Words..."
launch_calligra_document "/home/ga/Documents/board_minutes_q4.odt" "/tmp/calligra_words_task.log"

if ! wait_for_process "/usr/bin/calligrawords" 20; then
    wait_for_process "calligrawords" 15 || true
fi

if ! wait_for_window "Calligra Words\\|board_minutes_q4" 60; then
    echo "ERROR: Calligra Words window did not appear"
    cat /tmp/calligra_words_task.log || true
fi

wid=$(get_calligra_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid" || true
    safe_xdotool ga :1 key Escape || true
    sleep 0.5
    safe_xdotool ga :1 key ctrl+Home || true
fi

take_screenshot /tmp/calligra_board_minutes_sanitization_setup.png

echo "=== Board Minutes Sanitization Task Setup Complete ==="
