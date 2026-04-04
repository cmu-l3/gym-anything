#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Birding Log Result ==="

# Focus ONLYOFFICE and save
if is_onlyoffice_running; then
    echo "ONLYOFFICE is running, attempting to save..."
    focus_onlyoffice_window || true
    sleep 1
    
    # Save the document
    save_document ga :1
    sleep 2
    
    # Try to save again to ensure it's saved
    save_document ga :1
    sleep 1

    # Close ONLYOFFICE
    close_onlyoffice ga :1
    sleep 2
fi

# Ensure ONLYOFFICE is closed
if is_onlyoffice_running; then
    echo "Force closing ONLYOFFICE..."
    kill_onlyoffice ga
    sleep 1
fi

# Wait for file to be fully written
sleep 2

# Check if any birding log file was created
SPREADSHEETS_DIR="/home/ga/Documents/Spreadsheets"
echo "Checking for saved spreadsheet files in $SPREADSHEETS_DIR..."

if [ -d "$SPREADSHEETS_DIR" ]; then
    echo "Files in Spreadsheets directory:"
    ls -lh "$SPREADSHEETS_DIR" || echo "Directory is empty"
    
    # Look for recently created XLSX files
    RECENT_FILES=$(find "$SPREADSHEETS_DIR" -name "*.xlsx" -type f -mmin -10 2>/dev/null || true)
    
    if [ -n "$RECENT_FILES" ]; then
        echo "✅ Found recently created spreadsheet(s):"
        echo "$RECENT_FILES"
    else
        echo "⚠️ No recent XLSX files found in Spreadsheets directory"
    fi
else
    echo "⚠️ Spreadsheets directory does not exist"
fi

# Also check Desktop and Documents root in case agent saved elsewhere
for DIR in "/home/ga/Desktop" "/home/ga/Documents"; do
    if [ -d "$DIR" ]; then
        XLSX_FILES=$(find "$DIR" -maxdepth 1 -name "*.xlsx" -type f -mmin -10 2>/dev/null || true)
        if [ -n "$XLSX_FILES" ]; then
            echo "ℹ️ Found XLSX file(s) in $DIR:"
            echo "$XLSX_FILES"
        fi
    fi
done

echo "=== Export Complete ==="