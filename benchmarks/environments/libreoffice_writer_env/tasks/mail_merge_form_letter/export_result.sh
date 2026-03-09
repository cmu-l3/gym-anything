#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Mail Merge Result ==="

# Focus Writer window
wid=$(get_writer_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Do NOT force-save — the agent is responsible for saving.
# Just check which output files exist on disk.
for filepath in /home/ga/Documents/merged_letters.docx /home/ga/Documents/letter_template.docx; do
    if [ -f "$filepath" ]; then
        echo "File found: $filepath"
        ls -lh "$filepath"
    fi
done

# Close Writer (Ctrl+Q)
echo "Closing LibreOffice Writer..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 1

# Handle "Save changes?" dialog — press "Don't Save" to avoid
# masking agent failure (if they forgot to save, don't save for them)
safe_xdotool ga :1 key --delay 100 alt+d
sleep 0.5

echo "=== Export Complete ==="
