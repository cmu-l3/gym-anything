#!/bin/bash
set -e
echo "=== Setting up Procurement Flowchart Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create the source text file with workflow steps
mkdir -p /home/ga/Documents
cat > /home/ga/Documents/workflow_source.txt << 'EOF'
PROCUREMENT WORKFLOW STEPS

Instructions: Create a flowchart for the following process.
Use standard flowchart symbols (Oval=Start/End, Rectangle=Process, Diamond=Decision).
IMPORTANT: Use dynamic Connectors to link shapes, not static lines.

1. START: "Need Identified"
2. PROCESS: "Create Requisition"
3. DECISION: "Cost > $500?"
4. IF NO -> PROCESS: "Auto-Approve" -> (connect to End)
5. IF YES -> PROCESS: "Manager Review" -> (connect to End)
6. END: "Issue PO"

Finally, Group all objects together.
EOF

# Set permissions
chown ga:ga /home/ga/Documents/workflow_source.txt
chmod 644 /home/ga/Documents/workflow_source.txt

# Start LibreOffice Writer with a blank document
echo "Starting LibreOffice Writer..."
su - ga -c "DISPLAY=:1 libreoffice --writer --norestore &"

# Wait for Writer window
if ! wait_for_window "LibreOffice Writer" 60; then
    echo "ERROR: LibreOffice Writer failed to start"
    exit 1
fi

# Maximize window
WID=$(get_writer_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Open the Sidebar (often needed for properties/gallery) if not open
# F11 toggles styles, but Ctrl+F5 opens sidebar. Let's just ensure focus.
safe_xdotool ga :1 key Escape 2>/dev/null || true

# Capture initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="
echo "Source file created at: /home/ga/Documents/workflow_source.txt"