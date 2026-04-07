#!/bin/bash
echo "=== Setting up multi_language_cinematic_conforming task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Kill any existing Ardour instances
kill_ardour

SESSION_DIR="/home/ga/Audio/sessions/MyProject"
SESSION_FILE="$SESSION_DIR/MyProject.ardour"
BACKUP_FILE="$SESSION_DIR/MyProject.ardour.clean_backup"

# Create backup of clean session on first run
if [ ! -f "$BACKUP_FILE" ] && [ -f "$SESSION_FILE" ]; then
    cp "$SESSION_FILE" "$BACKUP_FILE"
    echo "Created clean session backup"
fi

# Restore clean session
if [ -f "$BACKUP_FILE" ]; then
    cp "$BACKUP_FILE" "$SESSION_FILE"
    echo "Restored clean session from backup"
fi

# Create directories
su - ga -c "mkdir -p /home/ga/Audio/localization"
su - ga -c "mkdir -p /home/ga/Audio/exports"
rm -f /home/ga/Audio/exports/*.wav 2>/dev/null || true

# Generate audio stems from existing samples
SAMPLES="/home/ga/Audio/samples"
LOC_DIR="/home/ga/Audio/localization"

# 1. M&E (Music and Effects)
if [ -f "$SAMPLES/moonlight_sonata.wav" ]; then
    ffmpeg -y -i "$SAMPLES/moonlight_sonata.wav" -t 30 -ar 44100 -ac 2 "$LOC_DIR/m_and_e.wav" 2>/dev/null
else
    cp $(find "$SAMPLES" -name "*.wav" | head -1) "$LOC_DIR/m_and_e.wav"
fi

# 2. English Dialogue
if [ -f "$SAMPLES/narration.wav" ]; then
    ffmpeg -y -i "$SAMPLES/narration.wav" -t 15 -ar 44100 -ac 1 "$LOC_DIR/dialogue_en.wav" 2>/dev/null
else
    cp $(find "$SAMPLES" -name "*.wav" | tail -1) "$LOC_DIR/dialogue_en.wav"
fi

# 3. Spanish Dialogue
if [ -f "$SAMPLES/good_morning.wav" ]; then
    ffmpeg -y -i "$SAMPLES/good_morning.wav" -t 15 -ar 44100 -ac 1 "$LOC_DIR/dialogue_es.wav" 2>/dev/null
else
    cp "$LOC_DIR/dialogue_en.wav" "$LOC_DIR/dialogue_es.wav"
fi

# 4. French Dialogue
if [ -f "$SAMPLES/good_morning.wav" ]; then
    ffmpeg -y -i "$SAMPLES/good_morning.wav" -ss 2 -t 15 -ar 44100 -ac 1 "$LOC_DIR/dialogue_fr.wav" 2>/dev/null
else
    cp "$LOC_DIR/dialogue_en.wav" "$LOC_DIR/dialogue_fr.wav"
fi

# Create instructions file
cat > "$LOC_DIR/instructions.txt" << 'EOF'
================================================================
CINEMATIC CONFORMING AND LOCALIZATION BRIEF
Project: "Urban Renewal" Cutscene 04
================================================================

STEPS:
1. Session Setup:
   - Import 'm_and_e.wav' and place it at exactly 0.0 seconds.
   - Import 'dialogue_en.wav' and place it at exactly 4.0 seconds.
   - Name these tracks appropriately (e.g., "Music & Effects", "Dialogue EN").

2. Language Conforming:
   - Create new tracks and import the Spanish ('dialogue_es.wav') and 
     French ('dialogue_fr.wav') stems.
   - Sync both the ES and FR dialogue regions so they start at the EXACT 
     same time as the English dialogue (4.0 seconds).

3. Localized Mixdowns:
   - Use track Mute buttons to isolate the correct languages.
   - Spanish Mix: Unmute M&E and Dialogue ES. Mute EN and FR.
     Export to: /home/ga/Audio/exports/cinematic_es.wav
   - French Mix: Unmute M&E and Dialogue FR. Mute EN and ES.
     Export to: /home/ga/Audio/exports/cinematic_fr.wav

4. Save the Ardour session when finished.
================================================================
EOF

chown -R ga:ga /home/ga/Audio/localization
chown -R ga:ga /home/ga/Audio/exports

# Launch Ardour
launch_ardour_session "$SESSION_FILE"
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="