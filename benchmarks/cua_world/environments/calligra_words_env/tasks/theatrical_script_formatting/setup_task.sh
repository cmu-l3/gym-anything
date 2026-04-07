#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Theatrical Script Formatting Task ==="

kill_calligra_processes

install -d -o ga -g ga /home/ga/Documents
install -d -o ga -g ga /home/ga/Desktop

rm -f /home/ga/Documents/the_bear_script.odt
rm -f /home/ga/Desktop/script_formatting_guide.txt

# ------------------------------------------------------------------
# 1. Create the Formatting Guide on the Desktop
# ------------------------------------------------------------------
cat > /home/ga/Desktop/script_formatting_guide.txt << 'EOF'
THEATRICAL SCRIPT FORMATTING GUIDE
==================================

Please format the attached raw script according to these standard theatrical conventions:

1. TITLE PAGE / HEADER
   - Play title ("THE BEAR"): Bold, large font (>=16pt), Centered
   - Subtitle and Author line: Centered

2. CHARACTER LIST
   - "DRAMATIS PERSONAE" must be formatted as a Heading (or bold >=14pt)

3. SCENE SETTING
   - The scene/setting description paragraph ("A drawing room in Popova's house.") must be fully italicized.

4. DIALOGUE & CHARACTER NAMES
   - Before every speech, the character's name (POPOVA, SMIRNOV, LUKA) must be BOLD.
   - Do not bold the actual spoken dialogue lines.

5. STAGE DIRECTIONS
   - All parenthetical actions (e.g., "(enters)", "(weeping)", "(aside)") must be italicized.

6. GENERAL TYPOGRAPHY
   - The body font must be readable and consistently sized (>=11pt).
EOF

chown ga:ga /home/ga/Desktop/script_formatting_guide.txt

# ------------------------------------------------------------------
# 2. Create the unformatted Chekhov play script using odfpy
# ------------------------------------------------------------------
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.text import P

doc = OpenDocumentText()

def add_paragraph(text=""):
    doc.text.addElement(P(text=text))

# Title elements (plain)
add_paragraph("THE BEAR")
add_paragraph("A Joke in One Act")
add_paragraph("by Anton Chekhov")
add_paragraph("")

# Character list
add_paragraph("DRAMATIS PERSONAE")
add_paragraph("ELENA IVANOVNA POPOVA, a landowning little widow, with dimples on her cheeks.")
add_paragraph("GRIGORY STEPANOVICH SMIRNOV, a middle-aged landowner.")
add_paragraph("LUKA, Popova's aged footman.")
add_paragraph("")

# Setting
add_paragraph("A drawing room in Popova's house.")
add_paragraph("")

# Dialogue (plain text, no bold or italics)
add_paragraph("POPOVA (looking at a photograph) I shall remain faithful to the grave...")
add_paragraph("LUKA It isn't right, madam... You're just destroying yourself... The maid and the cook have gone looking for berries, every living being is rejoicing, even the cat knows how to be happy, but you sit in the house all day.")
add_paragraph("POPOVA (weeping) My life is already at an end. He is in his grave, and I have buried myself between four walls... We are both dead.")
add_paragraph("LUKA (aside) Oh, Lord! (enters) There is someone asking for you, madam. He wants to see you.")
add_paragraph("POPOVA I suppose it is another of those creditors. Tell him I receive no one.")
add_paragraph("SMIRNOV (enters) I have the honour to present myself: Grigory Stepanovich Smirnov, landowner and retired lieutenant of artillery! I am compelled to disturb you on a very pressing affair.")
add_paragraph("POPOVA What do you want?")
add_paragraph("SMIRNOV Your late husband, with whom I had the honour to be acquainted, died in my debt. You must pay me my twelve hundred roubles.")
add_paragraph("POPOVA I have no ready money today. Tomorrow my steward will be back from town and I will give instructions for him to pay you.")
add_paragraph("SMIRNOV (jumps up) I'll stay and sit here until you give it to me! You will pay me tomorrow? Very well! I'll stay here all night!")
add_paragraph("POPOVA I have never in my life seen such impudence! I must ask you to leave!")
add_paragraph("SMIRNOV (stamps his foot) I'm not a steward, I'm a landowner! I won't be treated like this!")
add_paragraph("POPOVA You're a boor! A coarse bear! A Bourbon! A monster!")
add_paragraph("SMIRNOV What? What did you say? A bear? I invite you to a duel!")
add_paragraph("POPOVA (clutches at her heart) A duel? Very well! We shall fight! I will bring my husband's pistols.")
add_paragraph("SMIRNOV I will shoot her down like a partridge! I am not a man to be trifled with!")
add_paragraph("LUKA (falling on his knees) Master! Kind sir! Have pity on her and on me! Don't shoot her!")
add_paragraph("POPOVA (enters) Here are the pistols. But before we fight, you must show me how to fire. I have never held a pistol in my life.")
add_paragraph("SMIRNOV It's like this... My God, what eyes! What a woman! (aside) I am falling in love like a boy!")

doc.save("/home/ga/Documents/the_bear_script.odt")
PYEOF

chown ga:ga /home/ga/Documents/the_bear_script.odt

# ------------------------------------------------------------------
# 3. Launch Calligra Words
# ------------------------------------------------------------------
echo "Launching Calligra Words..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid calligrawords /home/ga/Documents/the_bear_script.odt >/tmp/calligra.log 2>&1 < /dev/null &"

# Wait for window
wait_for_window "Calligra Words" 30

WID=$(get_calligra_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# Dismiss welcome/tips dialog if any
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

take_screenshot /tmp/task_initial_state.png

echo "=== Task Setup Complete ==="