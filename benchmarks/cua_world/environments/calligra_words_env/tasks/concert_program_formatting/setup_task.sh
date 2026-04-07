#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Concert Program Formatting Task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

kill_calligra_processes

install -d -o ga -g ga /home/ga/Documents
install -d -o ga -g ga /home/ga/Desktop

rm -f /home/ga/Documents/concert_program.odt
rm -f /home/ga/Desktop/concert_program_style_guide.txt

# ------------------------------------------------------------------
# Create the unformatted concert program using odfpy
# ALL content is plain P elements — no heading styles, no formatting.
# ------------------------------------------------------------------
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.text import P

doc = OpenDocumentText()

def add_paragraph(text=""):
    doc.text.addElement(P(text=text))

# ── Title page elements ──
add_paragraph("Metropolitan Philharmonic Orchestra")
add_paragraph("2024–2025 Season")
add_paragraph("Masterworks Series IV: Echoes of the New World")
add_paragraph("Saturday, March 15, 2025 — 7:30 PM")
add_paragraph("Meridian Concert Hall")
add_paragraph("")
add_paragraph("Elena Vasquez, Music Director & Conductor")
add_paragraph("James Chen, Piano")
add_paragraph("")

# ── Program Order ──
add_paragraph("Program")
add_paragraph("Ludwig van Beethoven — Overture to Egmont, Op. 84")
add_paragraph("")
add_paragraph("Wolfgang Amadeus Mozart — Piano Concerto No. 21 in C major, K. 467")
add_paragraph("I. Allegro maestoso")
add_paragraph("II. Andante")
add_paragraph("III. Allegro vivace assai")
add_paragraph("")
add_paragraph("INTERMISSION")
add_paragraph("")
add_paragraph("Antonín Dvořák — Symphony No. 9 in E minor, Op. 95, \"From the New World\"")
add_paragraph("I. Adagio — Allegro molto")
add_paragraph("II. Largo")
add_paragraph("III. Scherzo: Molto vivace")
add_paragraph("IV. Allegro con fuoco")
add_paragraph("")

# ── Artist Biographies ──
add_paragraph("Artist Biographies")
add_paragraph("Elena Vasquez")
add_paragraph("Elena Vasquez is internationally recognized for her compelling interpretations and dynamic presence. As Music Director, she has transformed the orchestra's programming to include diverse contemporary voices alongside the classical canon.")
add_paragraph("")
add_paragraph("James Chen")
add_paragraph("James Chen has performed with major orchestras around the world. A graduate of the Juilliard School, his recent recording of the Mozart concertos won the prestigious Opus Klassik award. He frequently champions the works of underrepresented composers.")
add_paragraph("")
add_paragraph("Katerina Novotná")
add_paragraph("Katerina Novotná joined as Concertmaster in 2022. She brings extensive experience from her previous tenure with the Vienna Radio Symphony and frequently performs as a chamber musician throughout Europe and North America.")
add_paragraph("")

# ── Program Notes ──
add_paragraph("Program Notes")
add_paragraph("Egmont Overture")
add_paragraph("Beethoven composed the incidental music for Goethe's play Egmont during the Napoleonic Wars. The overture captures the heroic struggle and ultimate sacrifice of the protagonist, reflecting Beethoven's own political ideals and his belief in the triumph of human liberty.")
add_paragraph("")
add_paragraph("Piano Concerto No. 21")
add_paragraph("Mozart's Piano Concerto No. 21, often referred to as the Elvira Madigan due to its use in the 1967 Swedish film, showcases the composer's mature style. The famous Andante movement features a dreamlike melody that hovers over a pulsating accompaniment, creating an atmosphere of sublime serenity.")
add_paragraph("")
add_paragraph("New World Symphony")
add_paragraph("Dvořák composed his ninth symphony during his time as director of the National Conservatory in America. While incorporating elements of Native American and African American musical idioms, the work remains deeply rooted in the composer's Bohemian heritage. The iconic Largo movement is one of the most beloved in the symphonic repertoire.")
add_paragraph("")

# ── Acknowledgments ──
add_paragraph("Acknowledgments")
add_paragraph("The Board of Directors extends its deepest gratitude to the corporate sponsors and individual donors whose generous support makes this season possible. Special thanks to the Meridian Arts Council for their ongoing partnership and dedication to live symphonic music.")

doc.save("/home/ga/Documents/concert_program.odt")
PYEOF

chown ga:ga /home/ga/Documents/concert_program.odt

# ------------------------------------------------------------------
# Create the Style Guide
# ------------------------------------------------------------------
cat > /home/ga/Desktop/concert_program_style_guide.txt << 'EOF'
METROPOLITAN PHILHARMONIC ORCHESTRA
Concert Program Formatting Style Guide

Please apply the following typography rules to the concert program:

1. Orchestra Name: Bold weight, at least 18pt font size, Center aligned
2. Concert Title: Bold weight, at least 14pt font size, Center aligned
3. Date & Venue lines: Center aligned, regular weight
4. Composer Names: Bold weight (e.g., Ludwig van Beethoven)
5. Work Titles: Italic style (e.g., Overture to Egmont, Piano Concerto No. 21)
6. INTERMISSION marker: Center aligned, Bold weight
7. Artist Biography Names: Heading 2 style
8. "Program Notes" section header: Heading 1 style
9. Individual work note headers: Heading 2 style
10. "Acknowledgments" section header: Heading 1 style
11. Body Text (Biographies and Notes paragraphs): Justified alignment, at least 11pt font size
EOF

chown ga:ga /home/ga/Desktop/concert_program_style_guide.txt

# Launch Calligra Words with the document
launch_calligra_document "/home/ga/Documents/concert_program.odt" "/tmp/calligra_task.log"
sleep 5

# Focus and maximize window
WID=$(get_calligra_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot showing document loaded
take_screenshot /tmp/task_initial_state.png

echo "=== Setup Complete ==="