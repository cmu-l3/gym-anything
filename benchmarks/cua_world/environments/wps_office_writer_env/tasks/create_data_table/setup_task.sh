#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Create Data Table Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create a blank document that the agent will use to create the table
# This ensures WPS opens with a document ready for editing
echo "Creating blank document for table creation..."
python3 << 'PYEOF'
from docx import Document

doc = Document()
# Add a blank paragraph to ensure the document is valid
doc.add_paragraph("")
doc.save("/home/ga/Documents/new_report.docx")
print("Created blank document for Amazon sales report table")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/new_report.docx
sudo chmod 666 /home/ga/Documents/new_report.docx

# Launch WPS Writer with the blank document
echo "Launching WPS Writer with blank document..."
su - ga -c "DISPLAY=:1 QT_QPA_PLATFORMTHEME=gtk2 wps /home/ga/Documents/new_report.docx > /tmp/wps_task.log 2>&1 &"

# Wait for WPS to start
if ! wait_for_process "wps" 20; then
    echo "ERROR: WPS Writer failed to start"
    cat /tmp/wps_task.log
fi

# WPS may show EULA dialog first - wait for any WPS window to appear
echo "Waiting for WPS window (may be EULA dialog first)..."
sleep 5

# CRITICAL: Loop to ensure EULA is dismissed and WPS Writer window is visible
# This ensures the task start state shows the application, not the EULA dialog
max_eula_attempts=10
eula_attempt=0
wps_visible=false

while [ $eula_attempt -lt $max_eula_attempts ] && [ "$wps_visible" = "false" ]; do
    eula_attempt=$((eula_attempt + 1))
    echo "Verifying application state (attempt $eula_attempt/$max_eula_attempts)..."

    # Check for EULA dialog and dismiss it (broader pattern to catch variants)
    # Matches: "License Agreement", "Kingsoft Office Software", "End User License"
    if wmctrl -l | grep -qi "License Agreement\|Kingsoft\|End User License\|EULA"; then
        echo "EULA dialog detected, dismissing..."
        dismiss_wps_eula 3  # Reduced from 5 to 3 attempts per iteration
        sleep 2
    fi

    # Dismiss any other first-run dialogs
    dismiss_wps_dialogs
    sleep 1

    # Check if WPS Writer window is now visible (not EULA)
    # Also check that no EULA variants are present
    if wmctrl -l | grep -qi "Writer\|WPS" && ! wmctrl -l | grep -qi "License Agreement\|Kingsoft\|End User License\|EULA"; then
        echo "WPS Writer window is visible!"
        wps_visible=true
    else
        echo "WPS Writer window not yet visible, waiting..."
        sleep 2
    fi
done

if [ "$wps_visible" = "false" ]; then
    echo "ERROR: Could not get WPS Writer window visible after $max_eula_attempts attempts"
    echo "Current windows:"
    wmctrl -l
fi

# Wait for window to appear (WPS Writer or any WPS window)
if ! wait_for_window "WPS Writer\|WPS\|Writer" 20; then
    echo "Warning: Main WPS window not detected, checking processes..."
    pgrep -a wps || true
    echo "Window list:"
    wmctrl -l
fi

# Give WPS extra time to fully load
sleep 5

# Focus WPS window and verify
echo "Focusing WPS window..."
wid=$(get_wps_window_id)
if [ -n "$wid" ]; then
    if focus_window "$wid"; then
        sleep 1
    fi
fi

# CRITICAL: WPS shows its home screen after EULA dismissal, not the document
# We need a ROBUST retry loop to ensure document is open before proceeding
echo "Ensuring document is open (robust retry loop)..."

max_open_attempts=5
open_attempt=0
document_opened=false

while [ $open_attempt -lt $max_open_attempts ] && [ "$document_opened" = "false" ]; do
    open_attempt=$((open_attempt + 1))
    echo "Document open attempt $open_attempt/$max_open_attempts..."

    # Check if document is already open
    if wmctrl -l | grep -qi "new_report"; then
        echo "Document is open!"
        document_opened=true
        break
    fi

    echo "Document not open, trying to open it..."

    # Method 1: xdg-open (most reliable on Linux)
    echo "  Trying xdg-open..."
    su - ga -c "DISPLAY=:1 xdg-open /home/ga/Documents/new_report.docx" &
    sleep 4
    dismiss_wps_dialogs
    sleep 2

    if wmctrl -l | grep -qi "new_report"; then
        echo "  xdg-open succeeded!"
        document_opened=true
        break
    fi

    # Method 2: Navigate via Documents folder in WPS sidebar
    echo "  Trying Documents folder navigation..."
    # Click on Documents in sidebar: (165, 222) in 1280x720 = (247, 333) in 1920x1080
    DISPLAY=:1 xdotool mousemove 247 333
    sleep 0.3
    DISPLAY=:1 xdotool click 1
    sleep 3

    # Double-click on first file in the list
    DISPLAY=:1 xdotool mousemove 750 450
    sleep 0.3
    DISPLAY=:1 xdotool click --repeat 2 --delay 200 1
    sleep 3

    if wmctrl -l | grep -qi "new_report"; then
        echo "  Documents navigation succeeded!"
        document_opened=true
        break
    fi

    # Method 3: Ctrl+O file dialog
    echo "  Trying Ctrl+O file dialog..."
    DISPLAY=:1 xdotool key ctrl+o
    sleep 2
    DISPLAY=:1 xdotool type "/home/ga/Documents/new_report.docx"
    sleep 0.5
    DISPLAY=:1 xdotool key Return
    sleep 4

    if wmctrl -l | grep -qi "new_report"; then
        echo "  Ctrl+O succeeded!"
        document_opened=true
        break
    fi

    # Dismiss any dialogs before next attempt
    dismiss_wps_dialogs
    sleep 1
done

if [ "$document_opened" = "false" ]; then
    echo "ERROR: Failed to open document after $max_open_attempts attempts!"
    echo "Current windows:"
    wmctrl -l
fi

# Wait for document to fully load
sleep 3

# Move cursor to beginning of document
echo "Moving cursor to start of document..."
DISPLAY=:1 xdotool key ctrl+Home
sleep 0.5

# Wait for document content to fully render
echo "Waiting for document content to fully render..."
sleep 3

# CRITICAL: Dismiss any remaining dialogs that appeared after WPS loads
# WPS shows "System Check" and "WPS Office default" dialogs
echo "Dismissing any remaining dialogs..."
for i in 1 2 3; do
    # Try to close System Check dialog
    DISPLAY=:1 wmctrl -c "System Check" 2>/dev/null || true
    sleep 0.3
    # Try to close WPS Office default dialog by pressing Enter on OK button
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 0.3
    # Also try Escape
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.3
done
sleep 1

# CRITICAL: Verify final state before completing setup
# Take a verification screenshot to confirm WPS Writer is visible
echo "Taking verification screenshot..."
DISPLAY=:1 scrot /tmp/task_setup_verification.png 2>/dev/null || true

# Final window check - WPS Writer MUST be visible for task to proceed
final_windows=$(wmctrl -l 2>/dev/null)
if echo "$final_windows" | grep -qi "Writer\|WPS"; then
    if echo "$final_windows" | grep -qi "License Agreement\|Kingsoft"; then
        echo "WARNING: EULA dialog still visible at task start!"
    else
        echo "SUCCESS: WPS Writer window confirmed visible"
    fi
else
    echo "WARNING: WPS Writer window not detected in final check"
fi

echo "=== Create Data Table Task Setup Complete ==="
echo ""
echo "Instructions for the agent:"
echo "  Task: Create a sales report table using real Amazon Q4 2023 regional data"
echo "  Data Source: Amazon 2023 Annual Report and Statista regional revenue data"
echo ""
echo "  1. Add centered bold title: 'Amazon Q4 2023 Regional Net Sales Report'"
echo "  2. Create a 5x4 table (Insert > Table or use toolbar)"
echo "  3. Headers: Region | Q4 2023 Net Sales | Year-over-Year Growth | % of Total"
echo "  4. Data rows (real Amazon data from quarterly reports):"
echo "     - North America | \$105.5B | +13% | 62%"
echo "     - International | \$40.2B | +17% | 24%"
echo "     - AWS | \$24.2B | +13% | 14%"
echo "     - Total | \$170.0B | +14% | 100%"
echo "  5. Format header row: bold, blue background"
echo "  6. Right-align numeric columns"
echo "  7. Add alternating row colors"
echo "  8. Save as amazon_q4_report.docx (Ctrl+S or File > Save As)"
