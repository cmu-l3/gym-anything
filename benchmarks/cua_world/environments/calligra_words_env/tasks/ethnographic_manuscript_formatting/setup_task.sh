#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Ethnographic Manuscript Formatting Task ==="

kill_calligra_processes

install -d -o ga -g ga /home/ga/Documents
install -d -o ga -g ga /home/ga/Desktop

rm -f /home/ga/Documents/coastal_harvest_manuscript.odt
rm -f /home/ga/Desktop/university_press_guidelines.txt

# ------------------------------------------------------------------
# Create the publisher guidelines
# ------------------------------------------------------------------
cat > /home/ga/Desktop/university_press_guidelines.txt << 'EOF'
UNIVERSITY PRESS MANUSCRIPT FORMATTING GUIDELINES

Please ensure your manuscript adheres strictly to the following requirements before submission:

1. Chapter Headings:
   - All chapter titles ("Introduction", "Chapter 1: The Tides", "Chapter 2: Nets and Networks") must be formatted using the 'Heading 1' style.
   - Chapter titles must be Center-aligned.

2. Body Text:
   - The entire manuscript must use 1.5 line spacing.
   - All standard body paragraphs must have a 0.5-inch (1.27 cm) first-line indent.

3. Interview Transcripts (Block Quotes):
   - Any text representing an interview transcript must be formatted as a block quote.
   - Apply a 0.5-inch (1.27 cm) left margin AND a 0.5-inch (1.27 cm) right margin.
   - The font size for block quotes must be 10pt.
   - Block quotes must NOT have a first-line indent.
   - Delete the word "TRANSCRIPT:" from the beginning of these quotes.

4. Data Tables:
   - The raw participant demographic data must be converted into a formal 4-column table (Pseudonym, Age, Role, Years Active).
EOF

chown ga:ga /home/ga/Desktop/university_press_guidelines.txt

# ------------------------------------------------------------------
# Create the unformatted raw ethnographic manuscript using odfpy
# ------------------------------------------------------------------
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.text import P

doc = OpenDocumentText()

def add_paragraph(text=""):
    doc.text.addElement(P(text=text))

# ── Introduction ──
add_paragraph("Introduction")
add_paragraph(
    "The coastal communities of Maine have long relied on the ocean's bounty "
    "not just for economic sustenance, but as the foundation of their cultural "
    "identity. This ethnography explores the intersection of traditional fishing "
    "practices and modern regulatory pressures in three specific harbor towns. "
    "Through fourteen months of participant observation and semi-structured "
    "interviews, I document how these communities adapt to rapid ecological and "
    "legislative changes."
)
add_paragraph(
    "Methodologically, this research centers the voices of the fishermen "
    "themselves. By spending hundreds of hours on lobster boats, at harbor "
    "docks, and in local cooperatives, I sought to understand the lived reality "
    "of modern marine resource extraction. The narratives collected challenge "
    "monolithic views of environmental management."
)
add_paragraph("")

# ── Chapter 1 ──
add_paragraph("Chapter 1: The Tides")
add_paragraph(
    "In the early hours of the morning, the harbor comes alive with a rhythm "
    "dictated by the tides rather than the clock. Engines rumble to life before "
    "dawn, and the smell of diesel mixes with the salt air. It is in these quiet "
    "hours that the intergenerational transmission of knowledge is most apparent."
)
add_paragraph(
    "TRANSCRIPT: Well, I've been fishing these waters for forty years, and my "
    "father fished them for fifty before that. You don't learn where the ledges "
    "are from a chart or a GPS. You learn it by the color of the water, the way "
    "the current breaks, and the stories your elders told you while you were "
    "baiting bags as a boy. They can't regulate that kind of knowing."
)
add_paragraph(
    "This deep, localized ecological knowledge forms what anthropologists call "
    "a 'waterscape'—a mentally mapped territory that is fiercely defended and "
    "intimately understood. Yet, this waterscape is increasingly encroached upon "
    "by state and federal mandates."
)
add_paragraph(
    "TRANSCRIPT: When the quotas came down, we didn't know how we'd survive. "
    "They sit in an office in Boston and look at computer models. But the models "
    "don't account for how the water temperature shifts in our specific bay. "
    "We're seeing species move in ways the scientists haven't even published "
    "papers about yet."
)
add_paragraph("")

# ── Chapter 2 ──
add_paragraph("Chapter 2: Nets and Networks")
add_paragraph(
    "Regulatory frameworks often clash with traditional ecological knowledge. "
    "The transition from open-access fisheries to tightly controlled, limited-entry "
    "systems has fundamentally altered the social fabric of the harbor. Where "
    "once cooperation was necessary for survival, competition for scarce permits "
    "has sown discord."
)
add_paragraph(
    "TRANSCRIPT: My grandfather built this boat with his own hands. It was supposed "
    "to go to my son. But with the cost of a license now exceeding the value of "
    "the vessel itself, I had to sell the permit to a corporate outfit just to "
    "pay for my wife's medical bills. The boat sits idle now. It's like cutting "
    "off a limb."
)
add_paragraph(
    "The commodification of access rights has transformed a way of life into an "
    "asset class. This shift privileges capital over community, altering kinship "
    "networks that historically served as informal insurance policies during lean "
    "seasons."
)
add_paragraph(
    "TRANSCRIPT: They see us as an industry, but to us, it's our entire way of life. "
    "If you take the fishing out of this town, you don't just lose jobs. You lose "
    "the reason the town exists. You lose the shared language, the mutual aid, "
    "the very soul of the place."
)
add_paragraph("")

# ── Demographics ──
add_paragraph("Participant Demographics")
add_paragraph("Below is the demographic breakdown of key informants:")
add_paragraph("")
add_paragraph("Pseudonym, Age, Role, Years Active")
add_paragraph("Elias, 62, Captain, 45")
add_paragraph("Sarah, 34, Sternman, 12")
add_paragraph("Thomas, 58, Co-op Manager, 30")
add_paragraph("Marcus, 22, Apprentice, 3")
add_paragraph("Helen, 67, Retired Fleet Owner, 50")

doc.save("/home/ga/Documents/coastal_harvest_manuscript.odt")
PYEOF

chown ga:ga /home/ga/Documents/coastal_harvest_manuscript.odt

# ------------------------------------------------------------------
# Launch Calligra Words
# ------------------------------------------------------------------
echo "Launching Calligra Words..."
launch_calligra_document "/home/ga/Documents/coastal_harvest_manuscript.odt"

# Wait for application and maximize
for i in {1..30}; do
    WID=$(get_calligra_window_id)
    if [ -n "$WID" ]; then
        echo "Calligra Words window detected."
        sleep 2
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        focus_window "$WID"
        break
    fi
    sleep 1
done

sleep 2
take_screenshot /tmp/task_initial_state.png

echo "=== Task Setup Complete ==="