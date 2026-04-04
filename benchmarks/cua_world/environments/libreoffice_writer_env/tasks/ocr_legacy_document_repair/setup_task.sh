#!/bin/bash
# setup_task.sh - Generate messy OCR document and start Writer

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up OCR Legacy Document Repair Task ==="

# 1. Create task directories
sudo -u ga mkdir -p /home/ga/Documents

# 2. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt
chown ga:ga /tmp/task_start_time.txt

# 3. Generate the "messy" OCR document using Python
# We simulate a bad scan: hard wrap at 60 chars, hyphens at breaks, extra newlines.
echo "Generating 'bad OCR' document..."
python3 << 'PYEOF'
import textwrap
from docx import Document
from docx.shared import Pt

# The clean text (UDHR Preamble + Articles 1-5)
text_source = [
    "Universal Declaration of Human Rights",
    "Preamble",
    "Whereas recognition of the inherent dignity and of the equal and inalienable rights of all members of the human family is the foundation of freedom, justice and peace in the world,",
    "Whereas disregard and contempt for human rights have resulted in barbarous acts which have outraged the conscience of mankind, and the advent of a world in which human beings shall enjoy freedom of speech and belief and freedom from fear and want has been proclaimed as the highest aspiration of the common people,",
    "Whereas it is essential, if man is not to be compelled to have recourse, as a last resort, to rebellion against tyranny and oppression, that human rights should be protected by the rule of law,",
    "Whereas it is essential to promote the development of friendly relations between nations,",
    "Whereas the peoples of the United Nations have in the Charter reaffirmed their faith in fundamental human rights, in the dignity and worth of the human person and in the equal rights of men and women and have determined to promote social progress and better standards of life in larger freedom,",
    "Whereas Member States have pledged themselves to achieve, in co-operation with the United Nations, the promotion of universal respect for and observance of human rights and fundamental freedoms,",
    "Whereas a common understanding of these rights and freedoms is of the greatest importance for the full realization of this pledge,",
    "Now, therefore, The General Assembly proclaims this Universal Declaration of Human Rights as a common standard of achievement for all peoples and all nations, to the end that every individual and every organ of society, keeping this Declaration constantly in mind, shall strive by teaching and education to promote respect for these rights and freedoms and by progressive measures, national and international, to secure their universal and effective recognition and observance, both among the peoples of Member States themselves and among the peoples of territories under their jurisdiction.",
    "Article 1",
    "All human beings are born free and equal in dignity and rights. They are endowed with reason and conscience and should act towards one another in a spirit of brotherhood.",
    "Article 2",
    "Everyone is entitled to all the rights and freedoms set forth in this Declaration, without distinction of any kind, such as race, colour, sex, language, religion, political or other opinion, national or social origin, property, birth or other status. Furthermore, no distinction shall be made on the basis of the political, jurisdictional or international status of the country or territory to which a person belongs, whether it be independent, trust, non-self-governing or under any other limitation of sovereignty.",
    "Article 3",
    "Everyone has the right to life, liberty and security of person.",
    "Article 4",
    "No one shall be held in slavery or servitude; slavery and the slave trade shall be prohibited in all their forms.",
    "Article 5",
    "No one shall be subjected to torture or to cruel, inhuman or degrading treatment or punishment."
]

def mess_up_text(text, width=60):
    """
    Simulate bad OCR:
    - Hard wrap at 'width' characters.
    - If a word crosses the boundary, hyphenate it.
    """
    words = text.split()
    lines = []
    current_line = ""
    
    for word in words:
        # +1 for space
        if len(current_line) + len(word) + 1 <= width:
            current_line += (" " if current_line else "") + word
        else:
            # Word doesn't fit. 
            # If word is long enough (>4 chars), try to hyphenate split
            remaining_space = width - len(current_line) - 1 # space
            if len(word) > 4 and remaining_space > 2:
                # Simple split: put 'remaining_space' chars on this line with hyphen
                # and the rest on next.
                split_idx = remaining_space - 1 
                part1 = word[:split_idx] + "-"
                part2 = word[split_idx:]
                
                lines.append(current_line + (" " if current_line else "") + part1)
                current_line = part2
            else:
                # Just push to next line
                lines.append(current_line)
                current_line = word
    
    if current_line:
        lines.append(current_line)
    
    return lines

doc = Document()
# Use a monospaced font to make it look even more like a raw scan
style = doc.styles['Normal']
font = style.font
font.name = 'Courier New'
font.size = Pt(10)

for para_text in text_source:
    # Heading-like texts (short) usually don't get wrapped unless we force it,
    # but for this task, we treat everything as a stream of text that got wrapped.
    messy_lines = mess_up_text(para_text, width=55)
    
    for line in messy_lines:
        doc.add_paragraph(line)
    
    # Add an empty paragraph to denote the REAL paragraph break
    # This gives the agent a visual cue where the actual break should be.
    doc.add_paragraph("") 

doc.save("/home/ga/Documents/udhr_ocr_scan.docx")
PYEOF

# Set permissions
chown ga:ga /home/ga/Documents/udhr_ocr_scan.docx

# 4. Launch LibreOffice Writer
echo "Launching LibreOffice Writer..."
su - ga -c "DISPLAY=:1 libreoffice --writer --norestore /home/ga/Documents/udhr_ocr_scan.docx > /tmp/writer.log 2>&1 &"

# 5. Wait for window
wait_for_window "LibreOffice Writer" 60 || wait_for_window "udhr_ocr_scan" 30

# 6. Maximize and focus
wid=$(get_writer_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 7. Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="