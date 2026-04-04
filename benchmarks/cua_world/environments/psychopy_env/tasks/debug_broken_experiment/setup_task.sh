#!/bin/bash
echo "=== Setting up debug_broken_experiment task ==="

source /workspace/scripts/task_utils.sh

# Record task start time and generate nonce
record_task_start
generate_nonce

# Ensure target directories exist
mkdir -p /home/ga/PsychoPyExperiments/conditions
chown -R ga:ga /home/ga/PsychoPyExperiments

# Remove any pre-existing output file
rm -f /home/ga/PsychoPyExperiments/stroop_fixed.psyexp 2>/dev/null || true

# Ensure conditions file is available (this is the CORRECT file; the bug is in the experiment)
if [ ! -f /home/ga/PsychoPyExperiments/conditions/stroop_conditions.csv ]; then
    cp /workspace/assets/conditions/stroop_conditions.csv /home/ga/PsychoPyExperiments/conditions/
    chown ga:ga /home/ga/PsychoPyExperiments/conditions/stroop_conditions.csv
fi

# Generate the broken experiment file with 5 planted bugs
python3 << 'PYEOF'
import xml.etree.ElementTree as ET

# Build a realistic PsychoPy experiment XML with 5 intentional bugs
root = ET.Element("PsychoPy2experiment", encoding="utf-8", version="2025.2.4")

# === Settings ===
settings = ET.SubElement(root, "Settings")
for name, val in [
    ("expName", "broken_stroop"),
    ("Show info dlg", "True"),
    ("Monitor", "testMonitor"),
    ("Screen", "1"),
    ("Full-screen window", "False"),
    ("Window size (pixels)", "[1024, 768]"),
    ("color", "$[0,0,0]"),
    ("colorSpace", "rgb"),
    ("Units", "height"),
    ("Data filename", "'data/%s_%s_%s' % (expInfo['participant'], expName, expInfo['date'])"),
    ("Save csv file", "False"),
    ("Save excel file", "False"),
    ("Save psydat file", "True"),
    ("Save log file", "True"),
    ("logging level", "exp"),
    ("Use version", ""),
    ("HTML path", ""),
]:
    p = ET.SubElement(settings, "Param", name=name, val=val, valType="str" if isinstance(val, str) else "code")

# === Routines ===
routines = ET.SubElement(root, "Routines")

# -- instructions routine --
instr = ET.SubElement(routines, "Routine", name="instructions")
# Text component
instr_text = ET.SubElement(instr, "TextComponent", name="instr_text")
for name, val, vt in [
    ("name", "instr_text", "str"),
    ("text", "Welcome to the Stroop Task.\n\nYou will see color words displayed in colored ink.\nPress the key for the INK COLOR, not the word.\n\nleft = red    down = green    right = blue\n\nPress SPACE to begin.", "str"),
    ("color", "white", "str"),
    ("colorSpace", "rgb", "str"),
    ("opacity", "1", "num"),
    ("pos", "(0, 0)", "list"),
    ("size", "", "num"),
    ("ori", "0", "num"),
    ("startType", "time (s)", "str"),
    ("startVal", "0.0", "num"),
    ("stopType", "duration (s)", "str"),
    ("stopVal", "", "num"),
    ("startEstim", "", "num"),
    ("durationEstim", "", "num"),
    ("units", "from exp settings", "str"),
    ("font", "Arial", "str"),
    ("letterHeight", "0.05", "num"),
    ("wrapWidth", "0.8", "num"),
    ("flip", "", "str"),
    ("languageStyle", "LTR", "str"),
]:
    ET.SubElement(instr_text, "Param", name=name, val=val, valType=vt)

# Keyboard component for instructions
instr_key = ET.SubElement(instr, "KeyboardComponent", name="instr_key_resp")
for name, val, vt in [
    ("name", "instr_key_resp", "str"),
    ("allowedKeys", "'space'", "list"),
    ("startType", "time (s)", "str"),
    ("startVal", "0.0", "num"),
    ("stopType", "duration (s)", "str"),
    ("stopVal", "", "num"),
    ("forceEndRoutine", "True", "bool"),
    ("correctAns", "", "str"),
    ("store", "last key", "str"),
    ("storeCorrect", "False", "bool"),
    ("syncScreenRefresh", "True", "bool"),
]:
    ET.SubElement(instr_key, "Param", name=name, val=val, valType=vt)

# -- trial routine --
trial = ET.SubElement(routines, "Routine", name="trial")

# Text component for word display
# BUG #1: color field references $colour instead of $letterColor
word = ET.SubElement(trial, "TextComponent", name="word")
for name, val, vt in [
    ("name", "word", "str"),
    ("text", "$text", "str"),
    ("color", "$colour", "str"),   # <<< BUG: should be $letterColor
    ("colorSpace", "rgb", "str"),
    ("opacity", "1", "num"),
    ("pos", "(0, 0)", "list"),
    ("size", "", "num"),
    ("ori", "0", "num"),
    ("startType", "time (s)", "str"),
    ("startVal", "0.5", "num"),
    ("stopType", "duration (s)", "str"),
    ("stopVal", "2.0", "num"),
    ("startEstim", "", "num"),
    ("durationEstim", "", "num"),
    ("units", "from exp settings", "str"),
    ("font", "Arial", "str"),
    ("letterHeight", "0.1", "num"),
    ("wrapWidth", "", "num"),
    ("flip", "", "str"),
    ("languageStyle", "LTR", "str"),
]:
    ET.SubElement(word, "Param", name=name, val=val, valType=vt)

# Keyboard component
# BUG #2: allowedKeys is empty string (no keys accepted)
resp = ET.SubElement(trial, "KeyboardComponent", name="resp")
for name, val, vt in [
    ("name", "resp", "str"),
    ("allowedKeys", "", "list"),   # <<< BUG: empty — should be 'left','down','right'
    ("startType", "time (s)", "str"),
    ("startVal", "0.5", "num"),
    ("stopType", "duration (s)", "str"),
    ("stopVal", "2.0", "num"),
    ("forceEndRoutine", "True", "bool"),
    ("correctAns", "$corrAns", "str"),
    ("store", "last key", "str"),
    ("storeCorrect", "True", "bool"),
    ("syncScreenRefresh", "True", "bool"),
]:
    ET.SubElement(resp, "Param", name=name, val=val, valType=vt)

# Fixation cross
fix = ET.SubElement(trial, "TextComponent", name="fixation")
for name, val, vt in [
    ("name", "fixation", "str"),
    ("text", "+", "str"),
    ("color", "white", "str"),
    ("colorSpace", "rgb", "str"),
    ("opacity", "1", "num"),
    ("pos", "(0, 0)", "list"),
    ("startType", "time (s)", "str"),
    ("startVal", "0.0", "num"),
    ("stopType", "duration (s)", "str"),
    ("stopVal", "0.5", "num"),
    ("units", "from exp settings", "str"),
    ("font", "Arial", "str"),
    ("letterHeight", "0.1", "num"),
]:
    ET.SubElement(fix, "Param", name=name, val=val, valType=vt)

# === Flow ===
flow = ET.SubElement(root, "Flow")

# BUG #3: Instructions comes AFTER the trial loop (should be before)
# BUG #4: Loop nReps = 0 (no trials run)
# BUG #5: Conditions file path is wrong (stroop_conds.csv instead of stroop_conditions.csv)

loop_init = ET.SubElement(flow, "LoopInitiator", loopType="TrialHandler", name="trials")
for name, val, vt in [
    ("name", "trials", "str"),
    ("nReps", "0", "num"),   # <<< BUG: should be > 0
    ("conditions", "", "str"),
    ("conditionsFile", "conditions/stroop_conds.csv", "str"),  # <<< BUG: wrong filename
    ("endPoints", "[0, 1]", "list"),
    ("loopType", "random", "str"),
    ("isTrials", "True", "bool"),
]:
    ET.SubElement(loop_init, "Param", name=name, val=val, valType=vt)

ET.SubElement(flow, "Routine", name="trial")

loop_term = ET.SubElement(flow, "LoopTerminator", name="trials")

# BUG #3 continued: instructions AFTER the loop
ET.SubElement(flow, "Routine", name="instructions")

# Write the broken experiment
tree = ET.ElementTree(root)
ET.indent(tree, space="  ")
tree.write("/home/ga/PsychoPyExperiments/broken_stroop.psyexp",
           xml_declaration=True, encoding="utf-8")
print("Broken experiment created with 5 bugs:")
print("  1. $colour instead of $letterColor in text color")
print("  2. Empty allowedKeys in keyboard component")
print("  3. Instructions routine after trial loop in flow")
print("  4. Loop nReps = 0")
print("  5. Wrong conditions filename (stroop_conds.csv)")
PYEOF

chown ga:ga /home/ga/PsychoPyExperiments/broken_stroop.psyexp

# Ensure PsychoPy is running and focused on Builder
if ! is_psychopy_running; then
    echo "PsychoPy not running, launching..."
    su - ga -c "DISPLAY=:1 LIBGL_ALWAYS_SOFTWARE=1 PSYCHOPY_USERDIR=/home/ga/.psychopy3 psychopy &"
    wait_for_psychopy 30
    sleep 3
    dismiss_psychopy_dialogs
fi

focus_builder
maximize_window "$(get_builder_window)"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Task: Debug and fix the broken Stroop experiment"
echo "Broken file: /home/ga/PsychoPyExperiments/broken_stroop.psyexp"
echo "Save fixed version to: /home/ga/PsychoPyExperiments/stroop_fixed.psyexp"
