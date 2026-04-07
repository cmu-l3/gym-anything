#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Keynote Speech Formatting Task ==="

install -d -o ga -g ga /home/ga/Documents
install -d -o ga -g ga /home/ga/Desktop
kill_calligra_processes
rm -f /home/ga/Documents/keynote_draft.odt
rm -f /home/ga/Desktop/reading_script_spec.txt

cat > /home/ga/Desktop/reading_script_spec.txt << 'EOF'
PODIUM SCRIPT FORMATTING SPECIFICATION
======================================
To ensure the speaker does not lose their place while reading at the podium, please apply the following formatting to the draft:

1. Page Layout
   - Set Left and Right margins to exactly 2.00 inches to create a narrow reading column.
   
2. Typography
   - Select the main body of the speech and set Font Size to 18pt.
   - Set the Line Spacing to Double (200%) for readability.

3. Pagination
   - Insert a Page Break immediately before any line that begins with "SECTION: " (there are 3 such sections).

4. Stage Cues
   - There are 10 stage cues enclosed in brackets, such as [Pause for applause].
   - Format every bracketed cue to be BOTH Bold and Italic so they are visually distinct from spoken text.

5. Footer
   - Insert a Footer.
   - Type "EMBARGOED DRAFT" in the footer.
EOF
chown ga:ga /home/ga/Desktop/reading_script_spec.txt

python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.text import P

doc = OpenDocumentText()

lines = [
    "Address at Rice University on the Nation's Space Effort",
    "John F. Kennedy",
    "September 12, 1962",
    "",
    "[Pause for applause]",
    "We meet at a college noted for knowledge, in a city noted for progress, in a State noted for strength, and we stand in need of all three, for we meet in an hour of change and challenge, in a decade of hope and fear, in an age of both knowledge and ignorance. The greater our knowledge increases, the greater our ignorance unfolds.",
    "",
    "[Look at camera]",
    "Despite the striking fact that most of the scientists that the world has ever known are alive and working today, despite the fact that this Nation's own scientific manpower is doubling every 12 years in a rate of growth more than three times that of our population as a whole, despite that, the vast stretches of the unknown and the unanswered and the unfinished still far outstrip our collective comprehension.",
    "",
    "No man can fully grasp how far and how fast we have come, but condense, if you will, the 50,000 years of man's recorded history in a time span of but a half-century.",
    "",
    "[Gesture with right hand]",
    "SECTION: The New Ocean",
    "We set sail on this new sea because there is new knowledge to be gained, and new rights to be won, and they must be won and used for the progress of all people. For space science, like nuclear science and all technology, has no conscience of its own.",
    "",
    "[Look left]",
    "Whether it will become a force for good or ill depends on man, and only if the United States occupies a position of pre-eminence can we help decide whether this new ocean will be a sea of peace or a new terrifying theater of war.",
    "",
    "I do not say that we should or will go unprotected against the hostile misuse of space any more than we go unprotected against the hostile use of land or sea, but I do say that space can be explored and mastered without feeding the fires of war, without repeating the mistakes that man has made in extending his writ around this globe of ours.",
    "",
    "SECTION: The Choice",
    "[Lean forward]",
    "There is no strife, no prejudice, no national conflict in outer space as yet. Its hazards are hostile to us all. Its conquest deserves the best of all mankind, and its opportunity for peaceful cooperation may never come again. But why, some say, the moon? Why choose this as our goal? And they may well ask why climb the highest mountain?",
    "",
    "[Point to stadium]",
    "Why, 35 years ago, fly the Atlantic? Why does Rice play Texas?",
    "",
    "[Wait for laughter]",
    "We choose to go to the moon. We choose to go to the moon in this decade and do the other things, not because they are easy, but because they are hard, because that goal will serve to organize and measure the best of our energies and skills, because that challenge is one that we are willing to accept, one we are unwilling to postpone, and one which we intend to win, and the others, too.",
    "",
    "SECTION: The Future",
    "[Raise voice]",
    "It is for these reasons that I regard the decision last year to shift our efforts in space from low to high gear as among the most important decisions that will be made during my incumbency in the office of the Presidency.",
    "",
    "[Slow down]",
    "Well, space is there, and we're going to climb it, and the moon and the planets are there, and new hopes for knowledge and peace are there. And, therefore, as we set sail we ask God's blessing on the most hazardous and dangerous and greatest adventure on which man has ever embarked.",
    "",
    "[Final pause]"
]

for line in lines:
    doc.text.addElement(P(text=line))

doc.save("/home/ga/Documents/keynote_draft.odt")
PYEOF
chown ga:ga /home/ga/Documents/keynote_draft.odt

su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid calligrawords /home/ga/Documents/keynote_draft.odt >/tmp/calligra.log 2>&1 < /dev/null &"

wait_for_window "Calligra Words" 15
sleep 2

WID=$(get_calligra_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

take_screenshot /tmp/task_initial_state.png
echo "=== Setup complete ==="