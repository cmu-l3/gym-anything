#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Voter Pamphlet Layout Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

install -d -o ga -g ga /home/ga/Documents
kill_calligra_processes
rm -f /home/ga/Documents/voter_pamphlet.odt

# ---------------------------------------------------------------------------
# Create the unformatted Voter Pamphlet document (plain text, single column)
# ---------------------------------------------------------------------------
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.text import P

doc = OpenDocumentText()

def add_paragraph(text=""):
    doc.text.addElement(P(text=text))

# Main Title
add_paragraph("2026 Official Voter Information Pamphlet")
add_paragraph("")

# Measure A
add_paragraph("Measure A: School Facilities Bond")
add_paragraph("Impartial Analysis by the City Attorney")
add_paragraph(
    "The City Council has placed Measure A on the ballot to ask voters to approve "
    "a $120 million general obligation bond. The bond proceeds would be used to "
    "repair and upgrade aging school facilities, improve campus security systems, "
    "and construct new science and technology labs. If approved by 55% of the "
    "voters, the bond will be funded through an ad valorem tax on real property "
    "within the school district boundaries, estimated at $28 per $100,000 of "
    "assessed valuation annually."
)
add_paragraph("Argument in Favor")
add_paragraph(
    "To ensure our schools remain safe and equipped for the 21st century, we "
    "must vote YES on Measure A. Many of our local school buildings are over "
    "50 years old and suffer from failing roofs, outdated electrical systems, "
    "and inadequate security. Measure A includes strict accountability provisions, "
    "requiring independent citizen oversight and annual audits. No funds can "
    "be taken by the State or used for administrator salaries. Protect our "
    "children's future and property values by supporting our local schools."
)
add_paragraph("Elena Rostova, PTA President")
add_paragraph("Argument Against")
add_paragraph(
    "This bond will cost the average homeowner an additional $350 per year in "
    "property taxes. At a time when working families are struggling with inflation "
    "and rising costs of living, a massive tax increase is the wrong approach. "
    "The school district has failed to adequately maintain the facilities with "
    "the funds they already have. We should demand better financial management "
    "before handing over another blank check. Vote NO on Measure A."
)
add_paragraph("Patricia Chen, Coalition for Fair Taxes")
add_paragraph("")

# Measure B
add_paragraph("Measure B: Parks Maintenance Tax")
add_paragraph("Impartial Analysis by the City Attorney")
add_paragraph(
    "Measure B proposes a special parcel tax of $45 per year for single-family "
    "residential properties and varying rates for commercial properties, generating "
    "approximately $4.2 million annually for a period of ten years. The revenue "
    "must be deposited into a dedicated Parks and Recreation Fund and used "
    "exclusively for the maintenance, operation, and improvement of city parks, "
    "trails, and recreational facilities. As a special tax, Measure B requires "
    "a two-thirds (66.67%) affirmative vote for passage."
)
add_paragraph("Argument in Favor")
add_paragraph(
    "Measure B provides critical funding for our parks that cannot be diverted "
    "by the City Council. During the recent budget cuts, parks maintenance was "
    "slashed by 30%, resulting in overgrown trails, closed restrooms, and "
    "deteriorating playground equipment. This modest $45 annual assessment—less "
    "than $4 a month—will restore weekly maintenance schedules, repair broken "
    "equipment, and keep our green spaces safe and accessible for all residents. "
    "Vote YES for clean, safe parks."
)
add_paragraph("Dr. Sarah Lewis, Rivers Conservancy")
add_paragraph("Argument Against")
add_paragraph(
    "The city has a history of mismanaging funds, and Measure B is no exception. "
    "Just three years ago, voters approved a sales tax increase that was promised "
    "to cover essential city services, including parks. Now they are asking for "
    "more. Before raising taxes on homeowners, the city should streamline its "
    "bureaucracy and prioritize the existing budget. Throwing more money at a "
    "broken system will not fix our parks. We urge a NO vote."
)
add_paragraph("Marcus Johnson, Fire Chief")
add_paragraph("")

# Measure C
add_paragraph("Measure C: Mayoral Term Limits")
add_paragraph("Impartial Analysis by the City Attorney")
add_paragraph(
    "Under current law, the Mayor may serve an unlimited number of four-year "
    "terms. Measure C would amend the City Charter to restrict any individual "
    "from serving more than two consecutive four-year terms as Mayor. After "
    "serving two consecutive terms, an individual would be ineligible to hold "
    "the office of Mayor for a period of four years. The limits would apply "
    "prospectively, meaning current and past terms would not be counted. This "
    "measure requires a simple majority (50% plus one) for approval."
)
add_paragraph("Argument in Favor")
add_paragraph(
    "Term limits ensure fresh perspectives and prevent the entrenchment of "
    "political power. When incumbents remain in office for decades, they "
    "frequently become disconnected from the everyday concerns of the residents "
    "they are supposed to represent. Measure C will encourage new leadership "
    "and create a more competitive democratic process. Most neighboring cities "
    "already have term limits for their mayors. It is time we catch up. Vote "
    "YES on Measure C."
)
add_paragraph("David Kim, Citizens for Good Government")
add_paragraph("Argument Against")
add_paragraph(
    "Voters should have the right to retain experienced leadership if they "
    "choose to do so. Term limits are undemocratic because they restrict the "
    "choices available on the ballot. Complex municipal issues like housing "
    "and infrastructure require leaders with institutional knowledge and "
    "long-term vision. We already have term limits—they are called elections. "
    "If a mayor is not performing well, the voters can remove them at the "
    "ballot box. Vote NO on Measure C."
)
add_paragraph("Julia Gomez, Former City Manager")

doc.save("/home/ga/Documents/voter_pamphlet.odt")
PYEOF

chown ga:ga /home/ga/Documents/voter_pamphlet.odt

# Launch Calligra Words
launch_calligra_document "/home/ga/Documents/voter_pamphlet.odt" "/tmp/calligra_launch.log"

# Wait for application to be ready
wait_for_window "voter_pamphlet.odt" 30
sleep 2

# Maximize the window for full UI access
wid=$(get_calligra_window_id)
if [ -n "$wid" ]; then
    DISPLAY=:1 wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$wid"
fi

# Take an initial screenshot
take_screenshot "/tmp/task_initial.png"

echo "=== Setup complete ==="