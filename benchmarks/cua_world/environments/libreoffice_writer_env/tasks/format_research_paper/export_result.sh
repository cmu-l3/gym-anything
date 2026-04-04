#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Research Paper Formatting Result ==="

# Focus Writer window
wid=$(get_writer_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Do NOT force-save — the agent is responsible for saving.
# Just verify the file exists on disk.
if [ -f "/home/ga/Documents/raw_paper.docx" ]; then
    echo "File exists: /home/ga/Documents/raw_paper.docx"
    ls -lh /home/ga/Documents/raw_paper.docx
else
    echo "Warning: File not found on disk"
fi

# Close Writer (Ctrl+Q)
echo "Closing LibreOffice Writer..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 1

# Handle "Save changes?" dialog — press "Don't Save" to avoid
# masking agent failure (if they forgot to save, don't save for them)
safe_xdotool ga :1 key --delay 100 alt+d
sleep 0.5

echo "=== Export Complete ==="
