#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Oral History Compilation Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/TextDocuments"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the raw notes file with interview data
NOTES_FILE="$WORKSPACE_DIR/oral_history_notes.txt"

cat > "$NOTES_FILE" << 'EOF'
ORAL HISTORY NOTES - OLD MARKET DISTRICT
=======================================

INTERVIEWEES:
- Robert Chen, age 82, lived there 1955-1973, interviewed March 15, 2024
- Dorothy Williams, 78, lived there 1960-1972, interviewed March 18, 2024  
- James Murphy, 85, lived there 1952-1971, interviewed March 20, 2024
- Sarah Goldman, 80, lived there 1958-1974, interviewed March 22, 2024

KEY EVENTS (from interviews):
- 1956: Market district established as main commercial hub
- 1963: Highway construction announced (beginning of decline)
- 1968: Major fire at Goldman's Department Store
- 1970: City council votes for "urban renewal" demolition
- 1972: Final buildings demolished

MEMORABLE QUOTES:

Robert Chen said: "Every Saturday morning, the whole neighborhood came to the market. You could hear five different languages just walking one block. That was what made it special."

Dorothy Williams recalled: "When they announced the highway, we knew it was over. The city didn't care about preserving history - they just wanted to move cars faster."

James Murphy remembered: "The fire in '68 was the beginning of the end. After that, businesses started leaving one by one. By 1970, it was a ghost town."

Sarah Goldman noted: "My parents owned Goldman's Department Store for 30 years. Watching the bulldozers was like watching your childhood get erased."

HISTORICAL CONTEXT NOTES:
The Old Market District was typical of many urban neighborhoods demolished during the 1960s-70s urban renewal era. Like similar districts in cities across America, it fell victim to highway expansion and "slum clearance" policies that prioritized automobile infrastructure over community preservation.

FORMATTING REQUIREMENTS (from Historical Society):
1. Title: "Old Market District Oral History Project" - centered, bold, 16pt
2. Section headings: bold or Heading style, 14pt
3. Interviewees table: 4 columns (Name | Age | Years in District | Interview Date)
4. Timeline: Chronological order, years in bold
5. Quotes: Italic text with attribution line "— Name, Interview Date"
6. Historical Context: At least 50 words of narrative
EOF

chown ga:ga "$NOTES_FILE"

echo "✅ Notes file created at: $NOTES_FILE"

# Remove any existing output file
OUTPUT_FILE="$WORKSPACE_DIR/oral_history_final.docx"
rm -f "$OUTPUT_FILE"

# Launch ONLYOFFICE Document Editor with a new blank document
echo "Launching ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors --new:word > /tmp/onlyoffice_oral_history_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_oral_history_task.log || true
fi

# Wait for window
if ! wait_for_window "ONLYOFFICE" 30; then
    echo "ERROR: ONLYOFFICE window did not appear"
fi

# Protect ONLYOFFICE from OOM killer
protect_onlyoffice_from_oom

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 960 540 click 1" || true
sleep 1

# Focus ONLYOFFICE window
focus_onlyoffice_window

# Open the notes file in a text editor for reference (in background)
su - ga -c "DISPLAY=:1 xdg-open '$NOTES_FILE' > /dev/null 2>&1 &" || true
sleep 2

echo "=== Oral History Compilation Task Setup Complete ==="
echo "📝 Instructions:"
echo "  Reference notes available at: $NOTES_FILE"
echo "  Create formatted document at: $OUTPUT_FILE"
echo ""
echo "Required document structure:"
echo "  1. Title: 'Old Market District Oral History Project' (centered, bold, 16pt)"
echo "  2. Section: 'Interviewees' with 4-column table"
echo "      Columns: Name | Age | Years in District | Interview Date"
echo "      4 rows of data from notes"
echo "  3. Section: 'Key Events Timeline'"
echo "      Format: YEAR: Event description (year in bold)"
echo "      At least 4 events, chronologically ordered"
echo "  4. Section: 'Notable Accounts'"
echo "      At least 3 quotes in italic with attribution"
echo "      Format: Quote text (italic)"
echo "              — Name, Interview Date"
echo "  5. Section: 'Historical Context'"
echo "      Brief narrative (50+ words)"
echo "  6. Save as: /home/ga/Documents/TextDocuments/oral_history_final.docx"