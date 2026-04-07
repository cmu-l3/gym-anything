#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Luxury Itinerary Formatting Task ==="

# Record task start time
date +%s > /tmp/task_start_time

install -d -o ga -g ga /home/ga/Documents
install -d -o ga -g ga /home/ga/Desktop
kill_calligra_processes
rm -f /home/ga/Documents/japan_itinerary_draft.odt
rm -f /home/ga/Desktop/agency_style_guide.txt

cat > /home/ga/Desktop/agency_style_guide.txt << 'EOF'
LUXURY TRAVEL ITINERARY - FORMATTING STYLE GUIDE

Please ensure all client-facing itineraries follow these brand standards:

1. Main Title
   - Must be Bold
   - Must be Centered
   - Font size must be 18pt or larger

2. Table of Contents
   - Insert a Table of Contents immediately after the title so clients can quickly jump to specific days.

3. Heading Hierarchy
   - Heading 1: All Day titles (e.g., "Day 1: Arrival in Tokyo")
   - Heading 2: All Hotel designations (e.g., "Hotel: Aman Tokyo")
   - Heading 3: All Activity designations (e.g., "Activity: Welcome Dinner")

4. Flight Schedule
   - Convert the plain-text flight details into a proper 5-column table.
   - Columns: Date, Flight, Route, Departure, Arrival.

5. Body Text
   - All descriptive paragraphs for days and activities must be Justified for a clean, professional look.

6. Trip Inclusions
   - The "Trip Inclusions" section at the end must be formatted as a proper bulleted list (not just text dashes).
EOF
chown ga:ga /home/ga/Desktop/agency_style_guide.txt

# Create the unformatted itinerary using odfpy
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.text import P

doc = OpenDocumentText()

def add_paragraph(text=""):
    doc.text.addElement(P(text=text))

add_paragraph("Japan Grand Tour: Tokyo, Kyoto, & Beyond")
add_paragraph("")
add_paragraph("Flight Schedule:")
add_paragraph("Date | Flight | Route | Departure | Arrival")
add_paragraph("Oct 12 | JL 001 | SFO-HND | 13:00 | 16:25 (+1)")
add_paragraph("Oct 15 | NH 211 | HND-ITM | 09:00 | 10:10")
add_paragraph("Oct 20 | JL 112 | ITM-HND | 14:00 | 15:10")
add_paragraph("Oct 25 | JL 002 | HND-SFO | 18:00 | 11:00")
add_paragraph("")

add_paragraph("Day 1: Arrival in Tokyo")
add_paragraph("Hotel: Aman Tokyo")
add_paragraph("Activity: Welcome Dinner at Tsukiji")
add_paragraph("Arrive at Haneda Airport. You will be greeted by your private driver and transferred to the luxurious Aman Tokyo. In the evening, enjoy a welcome dinner near the historic Tsukiji outer market.")
add_paragraph("")

for day in range(2, 5):
    add_paragraph(f"Day {day}: Exploring Tokyo")
    add_paragraph("Hotel: Aman Tokyo")
    add_paragraph(f"Activity: Tokyo Tour Part {day}")
    add_paragraph("Enjoy a full day of guided tours in Tokyo tailored to your interests, complete with private transportation and expert local guides.")
    add_paragraph("")

add_paragraph("Day 5: Travel to Kyoto")
add_paragraph("Hotel: Ritz-Carlton Kyoto")
add_paragraph("Activity: Shinkansen Ride")
add_paragraph("Take the first-class Shinkansen (bullet train) from Tokyo to Kyoto. Enjoy the scenic view of Mount Fuji along the way.")
add_paragraph("")

for day in range(6, 14):
    if day == 6:
        add_paragraph("Day 6: Kyoto Heritage")
        add_paragraph("Hotel: Ritz-Carlton Kyoto")
        add_paragraph("Activity: Kinkaku-ji Visit")
        add_paragraph("Explore the iconic Kinkaku-ji (Golden Pavilion) and its magnificent Zen gardens. Experience a traditional tea ceremony in the afternoon.")
    else:
        add_paragraph(f"Day {day}: Kyoto and Surroundings")
        add_paragraph("Hotel: Ritz-Carlton Kyoto")
        add_paragraph(f"Activity: Kansai Exploration {day}")
        add_paragraph("Continue your exploration of the Kansai region with exclusive access to historic sites and culinary experiences.")
    add_paragraph("")

add_paragraph("Day 14: Departure")
add_paragraph("Hotel: None")
add_paragraph("Activity: Airport Transfer")
add_paragraph("Transfer to the airport for your departure flight. We hope you enjoyed your luxury journey through Japan.")
add_paragraph("")

add_paragraph("Trip Inclusions")
add_paragraph("- 13 nights luxury accommodation")
add_paragraph("- First-class Shinkansen tickets")
add_paragraph("- Private airport transfers")
add_paragraph("- Daily breakfast and select dinners")
add_paragraph("- English-speaking private guides")
add_paragraph("- Entrance fees to all scheduled activities")

doc.save("/home/ga/Documents/japan_itinerary_draft.odt")
PYEOF

chown ga:ga /home/ga/Documents/japan_itinerary_draft.odt

# Launch Calligra Words
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid calligrawords /home/ga/Documents/japan_itinerary_draft.odt >/tmp/calligra_launch.log 2>&1 < /dev/null &"

# Wait for window and maximize
wait_for_window "Calligra Words" 30

WID=$(get_calligra_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="