#!/bin/bash
echo "=== Setting up film_score_tempo_map task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time for anti-gaming check
date +%s > /tmp/task_start_time.txt

# Create cue sheet directory
CUE_DIR="/home/ga/Audio/cue_sheets"
mkdir -p "$CUE_DIR"

# Write the cue sheet (realistic film scoring document)
cat > "$CUE_DIR/midnight_garden_cue_sheet.txt" << 'CUEEOF'
===============================================================
        FILM SCORING CUE SHEET — CONFIDENTIAL
===============================================================

Project:    "The Midnight Garden" (Short Film, 4 min 22 sec)
Director:   Sarah Chen
Composer:   [Your Name]
Session:    /home/ga/Audio/sessions/MyProject/MyProject.ardour
Date:       2024-11-15
Revision:   Final locked picture

===============================================================
SCENE BREAKDOWN AND TEMPO MAP
===============================================================

Please configure the Ardour session tempo map as follows.
The audio track should be renamed to "Score Sketch".
Add a location marker at each section start for navigation.

---------------------------------------------------------------
SECTION 1 — "Prologue" (starts at Bar 1)
---------------------------------------------------------------
  Time Signature:  4/4
  Tempo:           72 BPM
  Duration:        8 bars
  Scene:           Slow pan across moonlit garden. Mist rising
                   from flower beds. Mysterious, contemplative.
  Musical note:    Sparse piano, sustained strings, no percussion.

---------------------------------------------------------------
SECTION 2 — "Chase" (starts at Bar 9)
---------------------------------------------------------------
  Time Signature:  4/4
  Tempo:           152 BPM
  Duration:        12 bars
  Scene:           Protagonist spots shadowy figure, pursues
                   through hedge maze. Quick cuts, handheld camera.
  Musical note:    Driving ostinato, staccato strings, timpani.

---------------------------------------------------------------
SECTION 3 — "Waltz" (starts at Bar 21)
---------------------------------------------------------------
  Time Signature:  3/4  *** NOTE: TIME SIGNATURE CHANGE ***
  Tempo:           108 BPM
  Duration:        12 bars
  Scene:           Flashback to 1920s garden party. Couples
                   dancing under paper lanterns. Warm golden light.
  Musical note:    Viennese waltz feel. Solo violin melody over
                   oom-pah-pah accompaniment.

---------------------------------------------------------------
SECTION 4 — "Finale" (starts at Bar 33)
---------------------------------------------------------------
  Time Signature:  4/4  *** NOTE: RETURN TO 4/4 ***
  Tempo:           132 BPM
  Duration:        To end
  Scene:           Garden restored. Morning light breaks through.
                   Protagonist smiles. Triumphant, emotional.
  Musical note:    Full orchestra, major key, soaring melody.
                   Building to final cadence.

===============================================================
SUMMARY TABLE
===============================================================

  Section     Bar    Time Sig    Tempo     Marker Name
  ---------   ---    --------    -----     -----------
  Prologue      1      4/4       72 BPM    "Prologue"
  Chase         9      4/4      152 BPM    "Chase"
  Waltz        21      3/4      108 BPM    "Waltz"
  Finale       33      4/4      132 BPM    "Finale"

===============================================================
ADDITIONAL INSTRUCTIONS
===============================================================

1. Set up the tempo map BEFORE recording begins.
2. Rename the main audio track to "Score Sketch".
3. Place a location marker at each section start.
4. Save the session when complete (Ctrl+S).

Thank you! Looking forward to hearing the first sketches.
— Sarah
===============================================================
CUEEOF

chown -R ga:ga "$CUE_DIR"
echo "Cue sheet written to $CUE_DIR/midnight_garden_cue_sheet.txt"

# Ensure session structure exists and kill any existing Ardour instance
pkill -f ardour 2>/dev/null || true
sleep 2

SESSION_DIR="/home/ga/Audio/sessions/MyProject"
SESSION_FILE="$SESSION_DIR/MyProject.ardour"

# Initialize clean backup if it doesn't exist to ensure a pristine state
BACKUP_FILE="$SESSION_DIR/MyProject.ardour.clean_backup"
if [ ! -f "$BACKUP_FILE" ] && [ -f "$SESSION_FILE" ]; then
    cp "$SESSION_FILE" "$BACKUP_FILE"
fi

# Always restore clean session
if [ -f "$BACKUP_FILE" ]; then
    cp "$BACKUP_FILE" "$SESSION_FILE"
fi

# Record session file state before task
if [ -f "$SESSION_FILE" ]; then
    stat -c %Y "$SESSION_FILE" > /tmp/session_mtime_before.txt
    # Count existing tempo entries for anti-gaming
    TEMPO_COUNT=$(grep -c '<Tempo ' "$SESSION_FILE" 2>/dev/null || echo "0")
    if [ "$TEMPO_COUNT" -eq 0 ]; then
        TEMPO_COUNT=$(grep -c '<Point ' "$SESSION_FILE" 2>/dev/null || echo "0")
    fi
    echo "$TEMPO_COUNT" > /tmp/initial_tempo_count.txt
fi

# Start Ardour
if type launch_ardour_session &>/dev/null; then
    launch_ardour_session "$SESSION_FILE"
else
    # Fallback to direct launch if util is missing
    su - ga -c "DISPLAY=:1 ardour8 '$SESSION_FILE' > /tmp/ardour.log 2>&1 &" || \
    su - ga -c "DISPLAY=:1 ardour '$SESSION_FILE' > /tmp/ardour.log 2>&1 &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "MyProject"; then
            break
        fi
        sleep 1
    done
    
    # Maximize and focus
    DISPLAY=:1 wmctrl -r "MyProject" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -a "MyProject" 2>/dev/null || true
fi

sleep 3

# Take initial screenshot for reference
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== film_score_tempo_map task setup complete ==="