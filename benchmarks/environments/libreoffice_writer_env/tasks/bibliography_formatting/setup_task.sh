#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Bibliography Formatting Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create document with 10 real citations in deliberately wrong/mixed formats
# All citations are from real, well-known publications in psychology
python3 << 'PYEOF'
from docx import Document
from docx.shared import Pt

doc = Document()

# No heading - agent must add "References" heading

# Citation 1: MLA format (should be APA) - Kahneman & Tversky
doc.add_paragraph(
    'Kahneman, Daniel, and Amos Tversky. "Prospect Theory: An Analysis of '
    'Decision Under Risk." Econometrica, vol. 47, no. 2, 1979, pp. 263-292.'
)

# Citation 2: Informal/incomplete - Bandura
doc.add_paragraph(
    'Social Learning Theory by Albert Bandura, published 1977 by '
    'Prentice Hall, Englewood Cliffs, NJ.'
)

# Citation 3: Chicago note style - Milgram
doc.add_paragraph(
    'Stanley Milgram, "Behavioral Study of Obedience," Journal of Abnormal '
    'and Social Psychology 67, no. 4 (1963): 371-378.'
)

# Citation 4: Wrong order, no italics - Skinner
doc.add_paragraph(
    'Skinner, B.F. (1938). The Behavior of Organisms: An Experimental '
    'Analysis. Appleton-Century-Crofts, New York.'
)

# Citation 5: Title first format - Piaget
doc.add_paragraph(
    'The Construction of Reality in the Child, Jean Piaget, translated by '
    'Margaret Cook, Basic Books, New York, 1954.'
)

# Citation 6: MLA style with "Print" - Maslow
doc.add_paragraph(
    'Maslow, Abraham H. "A Theory of Human Motivation." Psychological '
    'Review 50.4 (1943): 370-396. Print.'
)

# Citation 7: Nearly correct but wrong punctuation - Vygotsky
doc.add_paragraph(
    'Vygotsky, L.S. 1978. Mind in Society: The Development of Higher '
    'Psychological Processes, Harvard University Press. Cambridge, MA.'
)

# Citation 8: Full first names, MLA - Erikson
doc.add_paragraph(
    'Erikson, Erik H. Childhood and Society. New York: W.W. Norton, 1950.'
)

# Citation 9: Chicago bibliography style - Bowlby
doc.add_paragraph(
    'Bowlby, John. Attachment and Loss. Vol. 1, Attachment. New York: '
    'Basic Books, 1969.'
)

# Citation 10: Informal web-like citation - Pavlov
doc.add_paragraph(
    'Ivan Pavlov (1927). Conditioned Reflexes: An Investigation of the '
    'Physiological Activity of the Cerebral Cortex. Translated by G.V. '
    'Anrep. Oxford University Press. London.'
)

doc.save("/home/ga/Documents/raw_citations.docx")
print("Created document with 10 messy citations from real psychology publications")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/raw_citations.docx
sudo chmod 666 /home/ga/Documents/raw_citations.docx

# Launch LibreOffice Writer with the document
echo "Launching LibreOffice Writer..."
su - ga -c "DISPLAY=:1 libreoffice --writer --norestore /home/ga/Documents/raw_citations.docx > /tmp/writer_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/writer_task.log
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Writer" 90; then
    wait_for_window "raw_citations" 30 || true
fi

# Click on center of screen to select desktop
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus Writer window
echo "Focusing Writer window..."
wid=$(get_writer_window_id)
if [ -n "$wid" ]; then
    if focus_window "$wid"; then
        # Dismiss any "What's New" infobar that may appear on first launch
        safe_xdotool ga :1 key Escape
        sleep 0.3
        # Open Styles sidebar
        safe_xdotool ga :1 key F11
        sleep 0.5
    fi
fi

# Move cursor to beginning
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Bibliography Formatting Task Setup Complete ==="
echo "Instructions:"
echo "  1. Add centered 'References' heading at the top"
echo "  2. Reformat all 10 citations to APA 7th edition"
echo "  3. Author names: LastName, F. M."
echo "  4. Year in parentheses after authors"
echo "  5. Italicize journal/book titles (not article titles)"
echo "  6. Apply 0.5-inch hanging indent to all entries"
echo "  7. Sort alphabetically by first author's last name"
echo "  8. Save (Ctrl+S)"
