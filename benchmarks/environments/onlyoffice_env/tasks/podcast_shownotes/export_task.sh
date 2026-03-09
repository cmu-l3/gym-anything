#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Podcast Show Notes ==="

# First try to save with the new filename
if is_onlyoffice_running; then
    focus_onlyoffice_window || true
    
    # Try Save As to new filename: episode_12_shownotes.docx
    # We'll use Ctrl+Shift+S for Save As, then type the new name
    su - ga -c "DISPLAY=:1 xdotool key --delay 100 ctrl+shift+s" || true
    sleep 2
    
    # Type the new filename
    su - ga -c "DISPLAY=:1 xdotool type --delay 50 'episode_12_shownotes.docx'" || true
    sleep 1
    
    # Press Enter to save
    su - ga -c "DISPLAY=:1 xdotool key Return" || true
    sleep 2
    
    # Also try regular save
    save_document ga :1
    sleep 2

    # Close ONLYOFFICE
    close_onlyoffice ga :1
    sleep 2
fi

# Ensure ONLYOFFICE is closed
if is_onlyoffice_running; then
    kill_onlyoffice ga
fi

# Wait a moment for file to be fully written
sleep 1

EXPECTED_PATH="/home/ga/Documents/TextDocuments/episode_12_shownotes.docx"
ROUGH_PATH="/home/ga/Documents/TextDocuments/history_podcast_rough_notes.docx"

# Check if the file was saved with new name
if [ -f "$EXPECTED_PATH" ]; then
    echo "✅ Show notes saved as: $EXPECTED_PATH"
    ls -lh "$EXPECTED_PATH"
elif [ -f "$ROUGH_PATH" ]; then
    # If saved with original name, copy to expected name
    echo "⚠️ File saved with original name, copying to expected name"
    sudo -u ga cp "$ROUGH_PATH" "$EXPECTED_PATH"
    ls -lh "$EXPECTED_PATH"
else
    echo "⚠️ Show notes not found at: $EXPECTED_PATH"
fi

echo "=== Export Complete ==="