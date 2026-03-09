#!/bin/bash
set -e

echo "=== Closing Chrome to Save Preferences ==="

# Give Chrome time to process any pending operations
sleep 2

# Gracefully terminate Chrome to ensure Preferences file is written
if pgrep -f "chrome" > /dev/null; then
    echo "Sending TERM signal to Chrome..."
    pkill -TERM chrome || true
    
    # Wait for Chrome to exit gracefully
    sleep 3
    
    # Force kill if still running
    if pgrep -f "chrome" > /dev/null; then
        echo "Chrome still running, force killing..."
        pkill -9 chrome || true
        sleep 1
    fi
fi

# Verify Preferences file exists and was recently modified
PREFS_FILE="/home/ga/.config/google-chrome/Default/Preferences"
if [ -f "$PREFS_FILE" ]; then
    PREFS_SIZE=$(stat -c%s "$PREFS_FILE")
    echo "Preferences file found: $PREFS_SIZE bytes"
    
    # Check if file was modified in the last 2 minutes
    MTIME=$(stat -c%Y "$PREFS_FILE")
    NOW=$(date +%s)
    AGE=$((NOW - MTIME))
    
    if [ $AGE -lt 120 ]; then
        echo "Preferences file recently modified ($AGE seconds ago)"
    else
        echo "Warning: Preferences file may not have been updated ($AGE seconds old)"
    fi
else
    echo "Error: Preferences file not found!"
    exit 1
fi

echo "Chrome closed, preferences saved"
exit 0