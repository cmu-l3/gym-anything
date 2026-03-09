#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Fix Encoding Issue Result ==="

SCRIPT_FILE="/home/ga/workspace/encoding_project/analyze_data.py"

# Attempt to save the file one more time
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 1
} || {
    echo "⚠️ Failed to send save command; continuing"
}

# Wait a moment for file to be written
sleep 2

# Copy the final file to /tmp for verification
if [ -f "$SCRIPT_FILE" ]; then
    cp "$SCRIPT_FILE" /tmp/analyze_data_final.py
    
    # Detect the file encoding using 'file' command
    file -b --mime-encoding "$SCRIPT_FILE" > /tmp/detected_encoding.txt
    
    # Also get file size and modification time
    stat -c "%s %Y" "$SCRIPT_FILE" > /tmp/file_stats.txt
    
    echo "✅ File copied to /tmp/analyze_data_final.py"
    echo "Detected encoding: $(cat /tmp/detected_encoding.txt)"
else
    echo "❌ ERROR: Script file not found at $SCRIPT_FILE"
    echo "File not found" > /tmp/detected_encoding.txt
    echo "0 0" > /tmp/file_stats.txt
fi

echo "✅ Export complete"