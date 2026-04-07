#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Poetry Chapbook Typesetting Task ==="

sudo -u ga mkdir -p /home/ga/Documents

# Record task start time for anti-gaming verification
date +%s > /tmp/poetry_chapbook_start_time.txt

# Generate the raw manuscript document using python-docx
python3 << 'PYEOF'
from docx import Document
from docx.shared import Pt, Inches

doc = Document()

# Set standard 8.5x11 size with 1" margins to start (the raw unformatted state)
section = doc.sections[0]
section.page_width = Inches(8.5)
section.page_height = Inches(11.0)
section.left_margin = Inches(1.0)
section.right_margin = Inches(1.0)
section.top_margin = Inches(1.0)
section.bottom_margin = Inches(1.0)

# Unstyled Title Page
doc.add_paragraph("The Wild Swans at Coole")
doc.add_paragraph("By William Butler Yeats")
doc.add_paragraph("First Published 1919")
doc.add_paragraph("Independent Poetry Press Reprint Edition")
doc.add_page_break()

# TOC Placeholder
doc.add_paragraph("[INSERT TABLE OF CONTENTS HERE]")
doc.add_page_break()

# Poem 1
doc.add_paragraph("THE WILD SWANS AT COOLE")
doc.add_paragraph("The trees are in their autumn beauty,")
doc.add_paragraph("The woodland paths are dry,")
doc.add_paragraph("Under the October twilight the water")
doc.add_paragraph("Mirrors a still sky;")
doc.add_paragraph("Upon the brimming water among the stones")
doc.add_paragraph("Are nine-and-fifty swans.")
doc.add_paragraph("")
doc.add_paragraph("The nineteenth autumn has come upon me")
doc.add_paragraph("Since I first made my count;")
doc.add_paragraph("I saw, before I had well finished,")
doc.add_paragraph("All suddenly mount")
doc.add_paragraph("And scatter wheeling in great broken rings")
doc.add_paragraph("Upon their clamorous wings.")
doc.add_page_break()

# Poem 2
doc.add_paragraph("IN MEMORY OF MAJOR ROBERT GREGORY")
doc.add_paragraph("Now that we're almost settled in our house")
doc.add_paragraph("I'll name the friends that cannot sup with us")
doc.add_paragraph("Beside a fire of turf in th' ancient tower,")
doc.add_paragraph("And having talked to some late hour")
doc.add_paragraph("Climb up the narrow winding stair to bed:")
doc.add_paragraph("Discoverers of truth or beauty by daylight;")
doc.add_paragraph("And I'll name those who have perished:")
doc.add_paragraph("I have no friends that were not friends of his.")
doc.add_page_break()

# Poem 3
doc.add_paragraph("AN IRISH AIRMAN FORESEES HIS DEATH")
doc.add_paragraph("I know that I shall meet my fate")
doc.add_paragraph("Somewhere among the clouds above;")
doc.add_paragraph("Those that I fight I do not hate,")
doc.add_paragraph("Those that I guard I do not love;")
doc.add_paragraph("My country is Kiltartan Cross,")
doc.add_paragraph("My countrymen Kiltartan's poor,")
doc.add_paragraph("No likely end could bring them loss")
doc.add_paragraph("Or leave them happier than before.")
doc.add_page_break()

# Poem 4
doc.add_paragraph("MEN IMPROVE WITH THE YEARS")
doc.add_paragraph("I am worn out with dreams;")
doc.add_paragraph("A weather-worn, marble triton")
doc.add_paragraph("Among the streams;")
doc.add_paragraph("And all day long I look")
doc.add_paragraph("Upon this lady's beauty")
doc.add_paragraph("As though I had found in a book")
doc.add_paragraph("A pictured beauty,")
doc.add_paragraph("Pleased to have filled the eyes")
doc.add_paragraph("Or the discerning ears,")
doc.add_paragraph("Delighted to be but wise,")
doc.add_paragraph("For men improve with the years.")
doc.add_page_break()

# Poem 5
doc.add_paragraph("THE COLLAR-BONE OF A HARE")
doc.add_paragraph("Would I could cast a sail on the water")
doc.add_paragraph("Where many a king has gone")
doc.add_paragraph("And many a king's daughter,")
doc.add_paragraph("And alight at the comely trees and the lawn,")
doc.add_paragraph("The bothering rubbing of the dirt,")
doc.add_paragraph("And the crocus-colored dirt,")
doc.add_paragraph("And pierced by a white-tailed hare")
doc.add_paragraph("And danced upon the shore.")
doc.add_page_break()

# Poem 6
doc.add_paragraph("THE FISHERMAN")
doc.add_paragraph("Although I can see him still,")
doc.add_paragraph("The freckled man who goes")
doc.add_paragraph("To a grey place on a hill")
doc.add_paragraph("In grey Connemara clothes")
doc.add_paragraph("At dawn to cast his flies,")
doc.add_paragraph("It's long since I began")
doc.add_paragraph("To call up to the eyes")
doc.add_paragraph("This wise and simple man.")
doc.add_page_break()

# Poem 7
doc.add_paragraph("A SONG")
doc.add_paragraph("I thought no more was needed")
doc.add_paragraph("Youth to prolong")
doc.add_paragraph("Than dumb-bell and foil")
doc.add_paragraph("To keep the body young.")
doc.add_paragraph("O who could have foretold")
doc.add_paragraph("That the heart grows old?")

# Save raw manuscript
doc.save('/home/ga/Documents/yeats_raw.docx')
PYEOF

sudo chown ga:ga /home/ga/Documents/yeats_raw.docx

# Clear any previous task outputs
rm -f /home/ga/Documents/yeats_chapbook_print.docx

# Kill existing instances of WPS to ensure clean state
pkill -f "wps" || true
sleep 1

# Launch WPS Writer with the raw document
echo "Launching WPS Writer..."
su - ga -c "DISPLAY=:1 wps /home/ga/Documents/yeats_raw.docx &"
sleep 5

# Wait for WPS window to appear and maximize it
WID=""
for i in {1..15}; do
    WID=$(get_wps_window_id)
    if [ -n "$WID" ]; then
        echo "WPS Writer window found."
        break
    fi
    sleep 1
done

if [ -n "$WID" ]; then
    focus_window "$WID"
    # Maximize window
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    
    # Dismiss any "first run" or tip dialogs that could block the agent
    dismiss_wps_dialogs
    sleep 1
    
    # Refocus
    focus_window "$WID"
fi

# Take initial screenshot for verification reference
take_screenshot /tmp/poetry_chapbook_initial_state.png

echo "=== Task setup complete ==="