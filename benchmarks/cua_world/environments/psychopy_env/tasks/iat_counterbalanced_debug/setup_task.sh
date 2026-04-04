#!/bin/bash
echo "=== Setting up iat_counterbalanced_debug task ==="

source /workspace/scripts/task_utils.sh

record_task_start
generate_nonce

mkdir -p /home/ga/PsychoPyExperiments/conditions
chown -R ga:ga /home/ga/PsychoPyExperiments

# Remove any pre-existing output file to prevent do-nothing cheating
rm -f /home/ga/PsychoPyExperiments/iat_fixed.psyexp 2>/dev/null || true

# Create the broken IAT experiment file with 5 planted bugs
python3 << 'PYEOF'
import xml.etree.ElementTree as ET

root = ET.Element("PsychoPy2experiment", encoding="utf-8", version="2025.2.4")

# ====== Settings ======
settings = ET.SubElement(root, "Settings")
# BUG 5: participant variable without $ prefix in data filename
for name, val in [
    ("expName", "IAT_BlackWhite"),
    ("Show info dlg", "True"),
    ("Monitor", "testMonitor"),
    ("Screen", "1"),
    ("Full-screen window", "True"),
    ("Window size (pixels)", "[1024, 768]"),
    ("color", "$[-1,-1,-1]"),
    ("colorSpace", "rgb"),
    ("Units", "height"),
    ("Data filename", "'data/participant_IAT_%s' % expInfo['date']"),  # BUG 5: 'participant' not $participant
    ("Save csv file", "True"),
    ("Save excel file", "False"),
    ("Save psydat file", "True"),
    ("logging level", "exp"),
]:
    ET.SubElement(settings, "Param", name=name, val=val, valType="str")

# ====== Routines ======
routines = ET.SubElement(root, "Routines")

def make_text_routine(name, text_val, color_val="white", duration="", end_key="space"):
    """Helper to build a simple text+keyboard routine."""
    r = ET.SubElement(routines, "Routine", name=name)
    txt = ET.SubElement(r, "TextComponent", name=f"{name}_text")
    for pname, pval, pvt in [
        ("name", f"{name}_text", "str"),
        ("text", text_val, "str"),
        ("color", color_val, "str"),
        ("colorSpace", "rgb", "str"),
        ("opacity", "1", "num"),
        ("pos", "(0, 0)", "list"),
        ("ori", "0", "num"),
        ("startType", "time (s)", "str"),
        ("startVal", "0.0", "num"),
        ("stopType", "duration (s)", "str"),
        ("stopVal", duration, "num"),
        ("units", "from exp settings", "str"),
        ("font", "Arial", "str"),
        ("letterHeight", "0.04", "num"),
        ("wrapWidth", "0.9", "num"),
        ("languageStyle", "LTR", "str"),
    ]:
        ET.SubElement(txt, "Param", name=pname, val=pval, valType=pvt)

    if end_key:
        kb = ET.SubElement(r, "KeyboardComponent", name=f"{name}_key")
        for pname, pval, pvt in [
            ("name", f"{name}_key", "str"),
            ("allowedKeys", f"'{end_key}'", "list"),
            ("startType", "time (s)", "str"),
            ("startVal", "0.0", "num"),
            ("stopType", "duration (s)", "str"),
            ("stopVal", "", "num"),
            ("forceEndRoutine", "True", "bool"),
            ("store", "last key", "str"),
            ("storeCorrect", "False", "bool"),
            ("syncScreenRefresh", "True", "bool"),
        ]:
            ET.SubElement(kb, "Param", name=pname, val=pval, valType=pvt)
    return r

# Block 1 instructions: Attribute categorization practice
make_text_routine("block1_instr",
    "BLOCK 1\n\nSort items into categories.\n\nGOOD words (e-key): joy, love, peace, wonderful, laughter\nBAD words (i-key): agony, terrible, horrible, nasty, evil\n\nPress SPACE to begin.",
    end_key="space")

# Block 1 trial routine
b1_trial = ET.SubElement(routines, "Routine", name="b1_trial")
b1_word = ET.SubElement(b1_trial, "TextComponent", name="b1_word")
for pname, pval, pvt in [
    ("name", "b1_word", "str"),
    ("text", "$stimulus", "str"),
    ("color", "white", "str"),
    ("colorSpace", "rgb", "str"),
    ("opacity", "1", "num"),
    ("pos", "(0, 0)", "list"),
    ("ori", "0", "num"),
    ("startType", "time (s)", "str"),
    ("startVal", "0.0", "num"),
    ("stopType", "duration (s)", "str"),
    ("stopVal", "", "num"),
    ("units", "from exp settings", "str"),
    ("font", "Arial", "str"),
    ("letterHeight", "0.08", "num"),
    ("wrapWidth", "", "num"),
]:
    ET.SubElement(b1_word, "Param", name=pname, val=pval, valType=pvt)
b1_kb = ET.SubElement(b1_trial, "KeyboardComponent", name="b1_resp")
for pname, pval, pvt in [
    ("name", "b1_resp", "str"),
    ("allowedKeys", "'e','i'", "list"),
    ("startType", "time (s)", "str"),
    ("startVal", "0.0", "num"),
    ("stopType", "duration (s)", "str"),
    ("stopVal", "", "num"),
    ("forceEndRoutine", "True", "bool"),
    ("correctAns", "$corrAns", "str"),
    ("store", "first key", "str"),
    ("storeCorrect", "True", "bool"),
    ("syncScreenRefresh", "True", "bool"),
]:
    ET.SubElement(b1_kb, "Param", name=pname, val=pval, valType=pvt)

# Practice block instructions and trial (Block 2)
make_text_routine("block2_instr",
    "BLOCK 2 - PRACTICE\n\nNow sort faces by race.\n\nBlack faces (e-key)\nWhite faces (i-key)\n\nPress SPACE to begin.",
    end_key="space")

b2_trial = ET.SubElement(routines, "Routine", name="b2_trial")
b2_img = ET.SubElement(b2_trial, "ImageComponent", name="b2_face")
for pname, pval, pvt in [
    ("name", "b2_face", "str"),
    ("image", "$face_image", "str"),
    ("mask", "", "str"),
    ("color", "$white", "str"),
    # BUG 4: color references '$category_color' but conditions column is 'stim_color'
    ("pos", "(0, 0)", "list"),
    ("ori", "0", "num"),
    ("opacity", "1", "num"),
    ("size", "(0.3, 0.4)", "list"),
    ("startType", "time (s)", "str"),
    ("startVal", "0.0", "num"),
    ("stopType", "duration (s)", "str"),
    ("stopVal", "", "num"),
    ("units", "from exp settings", "str"),
]:
    ET.SubElement(b2_img, "Param", name=pname, val=pval, valType=pvt)

# Label text that uses wrong color variable
b2_label = ET.SubElement(b2_trial, "TextComponent", name="b2_label")
for pname, pval, pvt in [
    ("name", "b2_label", "str"),
    ("text", "$category_label", "str"),
    # BUG 4: references '$category_color' instead of '$stim_color'
    ("color", "$category_color", "str"),
    ("colorSpace", "rgb", "str"),
    ("opacity", "1", "num"),
    ("pos", "(0, -0.4)", "list"),
    ("ori", "0", "num"),
    ("startType", "time (s)", "str"),
    ("startVal", "0.0", "num"),
    ("stopType", "duration (s)", "str"),
    ("stopVal", "", "num"),
    ("units", "from exp settings", "str"),
    ("font", "Arial", "str"),
    ("letterHeight", "0.05", "num"),
    ("wrapWidth", "", "num"),
]:
    ET.SubElement(b2_label, "Param", name=pname, val=pval, valType=pvt)
b2_kb = ET.SubElement(b2_trial, "KeyboardComponent", name="b2_resp")
for pname, pval, pvt in [
    ("name", "b2_resp", "str"),
    ("allowedKeys", "'e','i'", "list"),
    ("startType", "time (s)", "str"),
    ("startVal", "0.0", "num"),
    ("stopType", "duration (s)", "str"),
    ("stopVal", "", "num"),
    ("forceEndRoutine", "True", "bool"),
    ("correctAns", "$corrAns", "str"),
    ("store", "first key", "str"),
    ("storeCorrect", "True", "bool"),
    ("syncScreenRefresh", "True", "bool"),
]:
    ET.SubElement(b2_kb, "Param", name=pname, val=pval, valType=pvt)

# Block 3 (Compatible: Black+Good/White+Bad) -- should be in flow BEFORE block 4
make_text_routine("block3_instr",
    "BLOCK 3 - CRITICAL\n\nNow both categories appear together.\n\nBlack faces OR Good words (e-key)\nWhite faces OR Bad words (i-key)\n\nPress SPACE to begin.",
    end_key="space")

b3_trial = ET.SubElement(routines, "Routine", name="b3_trial")
b3_stim = ET.SubElement(b3_trial, "TextComponent", name="b3_stimulus")
for pname, pval, pvt in [
    ("name", "b3_stimulus", "str"),
    ("text", "$stimulus", "str"),
    ("color", "white", "str"),
    ("colorSpace", "rgb", "str"),
    ("opacity", "1", "num"),
    ("pos", "(0, 0)", "list"),
    ("ori", "0", "num"),
    ("startType", "time (s)", "str"),
    ("startVal", "0.0", "num"),
    ("stopType", "duration (s)", "str"),
    ("stopVal", "", "num"),
    ("units", "from exp settings", "str"),
    ("font", "Arial", "str"),
    ("letterHeight", "0.08", "num"),
    ("wrapWidth", "", "num"),
]:
    ET.SubElement(b3_stim, "Param", name=pname, val=pval, valType=pvt)

# Code component with BUG 3: uses = instead of == (assignment vs comparison)
b3_code = ET.SubElement(b3_trial, "CodeComponent", name="b3_code")
for pname, pval, pvt in [
    ("name", "b3_code", "str"),
    ("Begin Experiment", "", "extendedCode"),
    ("Begin Routine", "", "extendedCode"),
    # BUG 3: uses = instead of == (will always be True due to assignment)
    ("Each Frame",
     "if b3_resp.keys:\n    if b3_resp.corr = 0:\n        errorBeep.play()\n",
     "extendedCode"),
    ("End Routine", "", "extendedCode"),
    ("End Experiment", "", "extendedCode"),
    ("Code Type", "Py", "str"),
]:
    ET.SubElement(b3_code, "Param", name=pname, val=pval, valType=pvt)

b3_kb = ET.SubElement(b3_trial, "KeyboardComponent", name="b3_resp")
for pname, pval, pvt in [
    ("name", "b3_resp", "str"),
    ("allowedKeys", "'e','i'", "list"),
    ("startType", "time (s)", "str"),
    ("startVal", "0.0", "num"),
    ("stopType", "duration (s)", "str"),
    ("stopVal", "", "num"),
    ("forceEndRoutine", "True", "bool"),
    ("correctAns", "$corrAns", "str"),
    ("store", "first key", "str"),
    ("storeCorrect", "True", "bool"),
    ("syncScreenRefresh", "True", "bool"),
]:
    ET.SubElement(b3_kb, "Param", name=pname, val=pval, valType=pvt)

# Block 4 (Incompatible: Black+Bad/White+Good) -- should be in flow AFTER block 3
make_text_routine("block4_instr",
    "BLOCK 4 - CRITICAL\n\nNow the combinations switch.\n\nWhite faces OR Good words (e-key)\nBlack faces OR Bad words (i-key)\n\nPress SPACE to begin.",
    end_key="space")

b4_trial = ET.SubElement(routines, "Routine", name="b4_trial")
b4_stim = ET.SubElement(b4_trial, "TextComponent", name="b4_stimulus")
for pname, pval, pvt in [
    ("name", "b4_stimulus", "str"),
    ("text", "$stimulus", "str"),
    ("color", "white", "str"),
    ("colorSpace", "rgb", "str"),
    ("opacity", "1", "num"),
    ("pos", "(0, 0)", "list"),
    ("ori", "0", "num"),
    ("startType", "time (s)", "str"),
    ("startVal", "0.0", "num"),
    ("stopType", "duration (s)", "str"),
    ("stopVal", "", "num"),
    ("units", "from exp settings", "str"),
    ("font", "Arial", "str"),
    ("letterHeight", "0.08", "num"),
    ("wrapWidth", "", "num"),
]:
    ET.SubElement(b4_stim, "Param", name=pname, val=pval, valType=pvt)
b4_kb = ET.SubElement(b4_trial, "KeyboardComponent", name="b4_resp")
for pname, pval, pvt in [
    ("name", "b4_resp", "str"),
    ("allowedKeys", "'e','i'", "list"),
    ("startType", "time (s)", "str"),
    ("startVal", "0.0", "num"),
    ("stopType", "duration (s)", "str"),
    ("stopVal", "", "num"),
    ("forceEndRoutine", "True", "bool"),
    ("correctAns", "$corrAns", "str"),
    ("store", "first key", "str"),
    ("storeCorrect", "True", "bool"),
    ("syncScreenRefresh", "True", "bool"),
]:
    ET.SubElement(b4_kb, "Param", name=pname, val=pval, valType=pvt)

make_text_routine("thanks",
    "The experiment is complete. Thank you for your participation.\n\nPress SPACE to exit.",
    end_key="space")

# ====== Flow ======
flow = ET.SubElement(root, "Flow")

# Block 1: attribute categorization
ET.SubElement(flow, "Routine", name="block1_instr")
loop1_init = ET.SubElement(flow, "LoopInitiator", loopType="TrialHandler", name="block1_loop")
for pname, pval, pvt in [
    ("name", "block1_loop", "str"),
    ("nReps", "2", "num"),
    ("conditions", "", "str"),
    ("conditionsFile", "conditions/iat_attr_conditions.csv", "str"),
    ("endPoints", "[0, 1]", "list"),
    ("loopType", "random", "str"),
    ("isTrials", "True", "bool"),
]:
    ET.SubElement(loop1_init, "Param", name=pname, val=pval, valType=pvt)
ET.SubElement(flow, "Routine", name="b1_trial")
ET.SubElement(flow, "LoopTerminator", name="block1_loop")

# Block 2: practice -- BUG 2: nReps = 0
ET.SubElement(flow, "Routine", name="block2_instr")
loop2_init = ET.SubElement(flow, "LoopInitiator", loopType="TrialHandler", name="block2_loop")
for pname, pval, pvt in [
    ("name", "block2_loop", "str"),
    ("nReps", "0", "num"),  # BUG 2: should be > 0
    ("conditions", "", "str"),
    ("conditionsFile", "conditions/iat_race_conditions.csv", "str"),
    ("endPoints", "[0, 1]", "list"),
    ("loopType", "random", "str"),
    ("isTrials", "True", "bool"),
]:
    ET.SubElement(loop2_init, "Param", name=pname, val=pval, valType=pvt)
ET.SubElement(flow, "Routine", name="b2_trial")
ET.SubElement(flow, "LoopTerminator", name="block2_loop")

# BUG 1: Block 4 (incompatible) BEFORE block 3 (compatible) -- order is wrong
# Correct order should be: block3 then block4
ET.SubElement(flow, "Routine", name="block4_instr")
loop4_init = ET.SubElement(flow, "LoopInitiator", loopType="TrialHandler", name="block4_loop")
for pname, pval, pvt in [
    ("name", "block4_loop", "str"),
    ("nReps", "4", "num"),
    ("conditions", "", "str"),
    ("conditionsFile", "conditions/iat_combined_incompatible.csv", "str"),
    ("endPoints", "[0, 1]", "list"),
    ("loopType", "random", "str"),
    ("isTrials", "True", "bool"),
]:
    ET.SubElement(loop4_init, "Param", name=pname, val=pval, valType=pvt)
ET.SubElement(flow, "Routine", name="b4_trial")
ET.SubElement(flow, "LoopTerminator", name="block4_loop")

ET.SubElement(flow, "Routine", name="block3_instr")
loop3_init = ET.SubElement(flow, "LoopInitiator", loopType="TrialHandler", name="block3_loop")
for pname, pval, pvt in [
    ("name", "block3_loop", "str"),
    ("nReps", "4", "num"),
    ("conditions", "", "str"),
    ("conditionsFile", "conditions/iat_combined_compatible.csv", "str"),
    ("endPoints", "[0, 1]", "list"),
    ("loopType", "random", "str"),
    ("isTrials", "True", "bool"),
]:
    ET.SubElement(loop3_init, "Param", name=pname, val=pval, valType=pvt)
ET.SubElement(flow, "Routine", name="b3_trial")
ET.SubElement(flow, "LoopTerminator", name="block3_loop")

ET.SubElement(flow, "Routine", name="thanks")

# Write the broken experiment file
tree = ET.ElementTree(root)
ET.indent(tree, space="  ")
tree.write("/home/ga/PsychoPyExperiments/iat_broken.psyexp",
           xml_declaration=True, encoding="utf-8")
print("IAT broken experiment created with 5 bugs:")
print("  BUG 1: Block 4 (incompatible) before Block 3 (compatible) in Flow")
print("  BUG 2: Block 2 practice loop nReps = 0 (no practice)")
print("  BUG 3: Code component uses = instead of == in b3_trial (Each Frame)")
print("  BUG 4: Label text color references '$category_color' (should be '$stim_color')")
print("  BUG 5: Data filename uses 'participant' not $participant variable")
print("  MISSING: No 'debrief' routine at end of Flow")
PYEOF

chown -R ga:ga /home/ga/PsychoPyExperiments

# Create the IAT conditions files (real IAT stimulus words from Greenwald et al. 1998)
python3 << 'PYEOF'
import csv, os

cond_dir = "/home/ga/PsychoPyExperiments/conditions"
os.makedirs(cond_dir, exist_ok=True)

# Attribute conditions: pleasant/unpleasant words (Greenwald, McGhee & Schwartz, 1998)
attr_rows = [
    {"stimulus": "joy", "category": "good", "corrAns": "e", "stim_color": "green"},
    {"stimulus": "love", "category": "good", "corrAns": "e", "stim_color": "green"},
    {"stimulus": "peace", "category": "good", "corrAns": "e", "stim_color": "green"},
    {"stimulus": "wonderful", "category": "good", "corrAns": "e", "stim_color": "green"},
    {"stimulus": "laughter", "category": "good", "corrAns": "e", "stim_color": "green"},
    {"stimulus": "agony", "category": "bad", "corrAns": "i", "stim_color": "red"},
    {"stimulus": "terrible", "category": "bad", "corrAns": "i", "stim_color": "red"},
    {"stimulus": "horrible", "category": "bad", "corrAns": "i", "stim_color": "red"},
    {"stimulus": "nasty", "category": "bad", "corrAns": "i", "stim_color": "red"},
    {"stimulus": "evil", "category": "bad", "corrAns": "i", "stim_color": "red"},
]
with open(os.path.join(cond_dir, "iat_attr_conditions.csv"), "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=["stimulus","category","corrAns","stim_color"])
    w.writeheader(); w.writerows(attr_rows)

# Race categorization (face labels used as text stimuli)
race_rows = [
    {"stimulus": "African American", "category": "black", "corrAns": "e", "stim_color": "white", "face_image": "face_placeholder.png", "category_label": "Black"},
    {"stimulus": "European American", "category": "white", "corrAns": "i", "stim_color": "white", "face_image": "face_placeholder.png", "category_label": "White"},
]
with open(os.path.join(cond_dir, "iat_race_conditions.csv"), "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=["stimulus","category","corrAns","stim_color","face_image","category_label"])
    w.writeheader(); w.writerows(race_rows)

# Compatible combined (Block 3): Black+Good share e-key, White+Bad share i-key
compat_rows = [
    {"stimulus": "joy", "category": "good", "corrAns": "e", "stim_color": "green"},
    {"stimulus": "love", "category": "good", "corrAns": "e", "stim_color": "green"},
    {"stimulus": "peace", "category": "good", "corrAns": "e", "stim_color": "green"},
    {"stimulus": "African American", "category": "black", "corrAns": "e", "stim_color": "white"},
    {"stimulus": "agony", "category": "bad", "corrAns": "i", "stim_color": "red"},
    {"stimulus": "terrible", "category": "bad", "corrAns": "i", "stim_color": "red"},
    {"stimulus": "horrible", "category": "bad", "corrAns": "i", "stim_color": "red"},
    {"stimulus": "European American", "category": "white", "corrAns": "i", "stim_color": "white"},
]
with open(os.path.join(cond_dir, "iat_combined_compatible.csv"), "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=["stimulus","category","corrAns","stim_color"])
    w.writeheader(); w.writerows(compat_rows)

# Incompatible combined (Block 4): White+Good share e-key, Black+Bad share i-key
incompat_rows = [
    {"stimulus": "joy", "category": "good", "corrAns": "e", "stim_color": "green"},
    {"stimulus": "love", "category": "good", "corrAns": "e", "stim_color": "green"},
    {"stimulus": "European American", "category": "white", "corrAns": "e", "stim_color": "white"},
    {"stimulus": "peace", "category": "good", "corrAns": "e", "stim_color": "green"},
    {"stimulus": "African American", "category": "black", "corrAns": "i", "stim_color": "white"},
    {"stimulus": "agony", "category": "bad", "corrAns": "i", "stim_color": "red"},
    {"stimulus": "terrible", "category": "bad", "corrAns": "i", "stim_color": "red"},
    {"stimulus": "horrible", "category": "bad", "corrAns": "i", "stim_color": "red"},
]
with open(os.path.join(cond_dir, "iat_combined_incompatible.csv"), "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=["stimulus","category","corrAns","stim_color"])
    w.writeheader(); w.writerows(incompat_rows)

print("IAT conditions files created")
PYEOF

chown -R ga:ga /home/ga/PsychoPyExperiments/conditions

# Ensure PsychoPy is running
if ! is_psychopy_running; then
    echo "Launching PsychoPy..."
    su - ga -c "DISPLAY=:1 LIBGL_ALWAYS_SOFTWARE=1 PSYCHOPY_USERDIR=/home/ga/.psychopy3 psychopy &"
    wait_for_psychopy 30
    sleep 3
    dismiss_psychopy_dialogs
fi

focus_builder
maximize_window "$(get_builder_window)"

sleep 2
take_screenshot /tmp/task_initial.png

echo "=== IAT debug task setup complete ==="
echo "Broken file: /home/ga/PsychoPyExperiments/iat_broken.psyexp"
echo "5 bugs planted; 1 debrief routine missing from Flow"
echo "Target output: /home/ga/PsychoPyExperiments/iat_fixed.psyexp"
