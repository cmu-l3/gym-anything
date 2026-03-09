#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Prepare Tutorial Snippet Result ==="

# Focus VSCode and save any open files
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+s
} || {
    echo "⚠️ Failed to save via Ctrl+S; continuing"
}

# Wait for tutorial file to be written
wait_for_file "/home/ga/workspace/tutorial/simple_rate_limiter.py" 3 || echo "Tutorial file may not exist yet"

# Give filesystem time to sync
sleep 2

# Export the tutorial file if it exists
TUTORIAL_FILE="/home/ga/workspace/tutorial/simple_rate_limiter.py"
if [ -f "$TUTORIAL_FILE" ]; then
    cp "$TUTORIAL_FILE" /tmp/simple_rate_limiter.py
    echo "✅ Tutorial file exported to /tmp/"
    
    # Export metadata for debugging
    wc -l "$TUTORIAL_FILE" > /tmp/tutorial_line_count.txt 2>/dev/null || echo "0" > /tmp/tutorial_line_count.txt
    echo "Line count: $(cat /tmp/tutorial_line_count.txt)"
else
    echo "⚠️ Tutorial file not found at $TUTORIAL_FILE"
    touch /tmp/simple_rate_limiter.py  # Create empty file so verifier doesn't fail on copy
fi

# Export original production file for reference
cp /home/ga/workspace/production/rate_limiter.py /tmp/production_rate_limiter.py 2>/dev/null || true

echo "✅ Export complete"
echo "Tutorial file: $TUTORIAL_FILE"