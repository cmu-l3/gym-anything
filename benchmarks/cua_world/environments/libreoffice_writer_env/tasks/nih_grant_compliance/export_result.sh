#!/bin/bash
# export_result.sh — NIH Grant Compliance Task

source /workspace/scripts/task_utils.sh

echo "=== Exporting NIH Grant Compliance Result ==="

# Focus Writer window (if open)
wid=$(get_writer_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Do NOT auto-save — agent must have saved already to /home/ga/Documents/r01_formatted.docx
# Report whether the output file exists
if [ -f "/home/ga/Documents/r01_formatted.docx" ]; then
    echo "Output file found: /home/ga/Documents/r01_formatted.docx"
    ls -lh /home/ga/Documents/r01_formatted.docx
else
    echo "WARNING: Output file not found at /home/ga/Documents/r01_formatted.docx"
fi

# Also check that the original draft still exists (agent must not overwrite it)
if [ -f "/home/ga/Documents/r01_draft.docx" ]; then
    echo "Original draft preserved: /home/ga/Documents/r01_draft.docx"
fi

# Close LibreOffice Writer without saving any additional changes
echo "Closing LibreOffice Writer..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 1
# Dismiss "Save changes?" dialog — click Don't Save
safe_xdotool ga :1 key --delay 100 alt+d
sleep 0.5

echo "=== Export Complete ==="
exit 0
