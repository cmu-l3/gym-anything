#!/bin/bash
echo "=== Setting up forensic_audio_segmentation task ==="

source /workspace/scripts/task_utils.sh

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

# Create evidence directories
su - ga -c "mkdir -p /home/ga/Audio/evidence_intake"
su - ga -c "mkdir -p /home/ga/Audio/evidence_output"
rm -f /home/ga/Audio/evidence_output/*.wav 2>/dev/null || true
rm -f /home/ga/Audio/evidence_output/*.txt 2>/dev/null || true

# Copy audio as evidence recording
SAMPLES_DIR="/home/ga/Audio/samples"
EVIDENCE_SRC=""
for f in "$SAMPLES_DIR"/art_of_war.wav "$SAMPLES_DIR"/moonlight_sonata.wav "$SAMPLES_DIR"/good_morning.wav; do
    if [ -f "$f" ]; then
        EVIDENCE_SRC="$f"
        break
    fi
done
if [ -z "$EVIDENCE_SRC" ]; then
    EVIDENCE_SRC=$(find "$SAMPLES_DIR" -name "*.wav" -type f | head -1)
fi

if [ -n "$EVIDENCE_SRC" ]; then
    cp "$EVIDENCE_SRC" /home/ga/Audio/evidence_intake/exhibit_A_recording.wav
    chown ga:ga /home/ga/Audio/evidence_intake/exhibit_A_recording.wav
fi

# Create evidence intake form
cat > /home/ga/Audio/evidence_intake/intake_form.txt << 'FORM'
================================================================
COUNTY CRIME LAB - AUDIO EVIDENCE INTAKE FORM
================================================================
Case Number:     2024-CR-0847
Case Title:      State v. Thompson
Evidence Item:   Exhibit A - Audio Recording
Submitted by:    Det. Maria Martinez, Badge #4521
Date Received:   2024-11-15
Lab File #:      AE-2024-1547

SOURCE FILE: exhibit_A_recording.wav
(Located in this directory)
================================================================

ANALYSIS REQUEST:

1. TRACK LABELING:
   Rename the main audio track to:
   "Exhibit A - Case 2024-CR-0847"

2. SEGMENT IDENTIFICATION:
   Create range markers (or point markers at segment boundaries)
   for the following identified portions of the recording:

   Segment 1: "Background Noise"
     - Start: 0:00 (sample 0)
     - End:   0:05 (sample 220500)

   Segment 2: "Speaker 1 - Defendant"
     - Start: 0:05 (sample 220500)
     - End:   0:15 (sample 661500)

   Segment 3: "Unintelligible Crosstalk"
     - Start: 0:15 (sample 661500)
     - End:   0:18 (sample 793800)

   Segment 4: "Speaker 2 - Complainant"
     - Start: 0:18 (sample 793800)
     - End:   0:25 (sample 1102500)

   Segment 5: "Ambient Noise Tail"
     - Start: 0:25 (sample 1102500)
     - End:   0:30 (sample 1323000)

3. SEGMENT EXPORT:
   Export each segment as a separate WAV file to:
   /home/ga/Audio/evidence_output/

   Use filenames:
     segment_01_background.wav
     segment_02_speaker1_defendant.wav
     segment_03_crosstalk.wav
     segment_04_speaker2_complainant.wav
     segment_05_ambient_tail.wav

4. CHAIN OF CUSTODY DOCUMENTATION:
   Create a text file at:
   /home/ga/Audio/evidence_output/chain_of_custody.txt

   Must include ALL of the following:
     - Case number (2024-CR-0847)
     - Exhibit ID (Exhibit A)
     - Lab file number (AE-2024-1547)
     - Examiner name/identifier
     - Date of analysis
     - Description of each segment (5 segments)
     - Statement that original recording was not altered

5. PRESERVATION:
   The original audio region must remain intact in the session.
   Do NOT delete or destructively edit the evidence recording.

================================================================
NOTES:
- All exports must be WAV format, matching the source sample rate
- Maintain professional forensic standards throughout
- Document all actions in the chain of custody log
================================================================
FORM

chown ga:ga /home/ga/Audio/evidence_intake/intake_form.txt

# Record baseline state
SESSION_FILE_PATH="/home/ga/Audio/sessions/MyProject/MyProject.ardour"
if [ -f "$SESSION_FILE_PATH" ]; then
    INITIAL_TRACK_COUNT=$(grep -c '<Route.*default-type="audio"' "$SESSION_FILE_PATH" 2>/dev/null || echo "0")
    INITIAL_MARKER_COUNT=$(grep -c '<Location.*IsMark' "$SESSION_FILE_PATH" 2>/dev/null || echo "0")
    echo "$INITIAL_TRACK_COUNT" > /tmp/initial_track_count
    echo "$INITIAL_MARKER_COUNT" > /tmp/initial_marker_count
fi

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Launch Ardour with the existing session
launch_ardour_session "$SESSION_FILE"

sleep 3

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "Evidence intake at /home/ga/Audio/evidence_intake/"
