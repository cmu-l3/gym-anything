#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Format Business Letter Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create the draft business letter document
# This uses REAL company information from Microsoft Corporation
# Microsoft HQ address from: https://www.microsoft.com/en-us/about/office-locations
python3 << 'PYEOF'
from docx import Document
from docx.shared import Pt

doc = Document()

# The letter content is provided as raw text without any formatting
# The agent must add sender/recipient addresses, date, and apply formatting
# Using real company: Microsoft Corporation, Redmond, WA

# Body text (unformatted) - the agent needs to add addresses and format this
doc.add_paragraph(
    "I am writing to express my strong interest in the Senior Software Engineer "
    "position at Microsoft Corporation, as advertised on your careers website. With "
    "over eight years of experience in full-stack development and a proven track "
    "record of delivering high-quality software solutions, I am confident that I "
    "would be a valuable addition to your engineering team."
)

doc.add_paragraph(
    "In my current role at Amazon Web Services, I have led the development of several "
    "enterprise-scale cloud services serving over 500,000 active users. My expertise "
    "includes Python, C#, .NET, React, and cloud technologies including Azure and AWS. "
    "I have consistently delivered projects on time and within budget, "
    "while maintaining the highest standards of code quality and documentation."
)

doc.add_paragraph(
    "What particularly excites me about Microsoft is your commitment to empowering "
    "every person and organization on the planet to achieve more. I have followed your "
    "recent innovations in AI and cloud computing with great interest and believe my "
    "background in secure, scalable distributed systems would align well with your "
    "mission to democratize artificial intelligence."
)

doc.add_paragraph(
    "I am particularly drawn to the collaborative culture at Microsoft, as evidenced "
    "by your open-source contributions to VS Code, TypeScript, and .NET. I am eager to "
    "contribute my skills and learn from your talented team."
)

doc.add_paragraph(
    "I would welcome the opportunity to discuss how my experience and skills could "
    "benefit Microsoft Corporation. Thank you for considering my application. I look "
    "forward to hearing from you soon."
)

doc.save("/home/ga/Documents/draft_letter.docx")
print("Created draft business letter document with real Microsoft Corporation data")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/draft_letter.docx
sudo chmod 666 /home/ga/Documents/draft_letter.docx

# Launch WPS Writer with the document
echo "Launching WPS Writer..."
su - ga -c "DISPLAY=:1 QT_QPA_PLATFORMTHEME=gtk2 wps /home/ga/Documents/draft_letter.docx > /tmp/wps_task.log 2>&1 &"

# Wait for WPS to start
if ! wait_for_process "wps" 20; then
    echo "ERROR: WPS Writer failed to start"
    cat /tmp/wps_task.log
fi

# WPS may show EULA dialog first - wait for any WPS window to appear
echo "Waiting for WPS window (may be EULA dialog first)..."
sleep 5

# CRITICAL: Loop to ensure EULA is dismissed and document window is visible
# This ensures the task start state shows the document, not the EULA dialog
max_eula_attempts=10
eula_attempt=0
document_visible=false

while [ $eula_attempt -lt $max_eula_attempts ] && [ "$document_visible" = "false" ]; do
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

    # Check if document window is now visible (not EULA)
    # Also check that no EULA variants are present
    if wmctrl -l | grep -qi "draft_letter\|Writer" && ! wmctrl -l | grep -qi "License Agreement\|Kingsoft\|End User License\|EULA"; then
        echo "Document window is visible!"
        document_visible=true
    else
        echo "Document window not yet visible, waiting..."
        sleep 2
    fi
done

if [ "$document_visible" = "false" ]; then
    echo "ERROR: Could not get document window visible after $max_eula_attempts attempts"
    echo "Current windows:"
    wmctrl -l
fi

# Wait for window to appear (WPS Writer or document name)
if ! wait_for_window "WPS Writer\|draft_letter\|Writer" 20; then
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

# Helper function to check if document is open
# WPS may show "draft_letter" in title, or just ".docx" or "Writer" with document content loaded
check_document_open() {
    local win_list=$(wmctrl -l 2>/dev/null)
    # Check for document name in window title
    if echo "$win_list" | grep -qi "draft_letter"; then
        return 0
    fi
    # Check for .docx in window title (WPS sometimes shows this)
    if echo "$win_list" | grep -qi "\.docx"; then
        return 0
    fi
    # If WPS Writer is showing but NOT the home screen (home screen has "WPS Office" as full window title)
    # The home screen shows "WPS Writer" in the title bar but the wmctrl reports it differently
    # Check if there's a Writer window AND the window title contains document indicators
    if echo "$win_list" | grep -i "Writer" | grep -qiv "WPS Office$"; then
        # Could be document open - need to verify by checking if home screen elements are gone
        # The home screen has specific elements like "Recent Visit" and "No Filter Result"
        # We can't easily detect this from wmctrl, so we'll use a secondary check
        return 0
    fi
    return 1
}

max_open_attempts=8
open_attempt=0
document_opened=false

while [ $open_attempt -lt $max_open_attempts ] && [ "$document_opened" = "false" ]; do
    open_attempt=$((open_attempt + 1))
    echo "Document open attempt $open_attempt/$max_open_attempts..."

    # Check if document is already open
    if check_document_open; then
        echo "Document appears to be open!"
        document_opened=true
        break
    fi

    echo "Document not open, trying to open it..."

    # Method 1: xdg-open (most reliable on Linux)
    echo "  Trying xdg-open..."
    su - ga -c "DISPLAY=:1 xdg-open /home/ga/Documents/draft_letter.docx" &
    sleep 5
    dismiss_wps_dialogs
    sleep 2

    if check_document_open; then
        echo "  xdg-open succeeded!"
        document_opened=true
        break
    fi

    # Method 2: Direct wps command with document
    echo "  Trying direct wps command..."
    su - ga -c "DISPLAY=:1 wps /home/ga/Documents/draft_letter.docx" &
    sleep 5
    dismiss_wps_dialogs
    sleep 2

    if check_document_open; then
        echo "  Direct wps command succeeded!"
        document_opened=true
        break
    fi

    # Method 3: Navigate via Documents folder in WPS sidebar
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

    if check_document_open; then
        echo "  Documents navigation succeeded!"
        document_opened=true
        break
    fi

    # Method 4: Ctrl+O file dialog
    echo "  Trying Ctrl+O file dialog..."
    DISPLAY=:1 xdotool key ctrl+o
    sleep 2
    DISPLAY=:1 xdotool type "/home/ga/Documents/draft_letter.docx"
    sleep 0.5
    DISPLAY=:1 xdotool key Return
    sleep 5

    if check_document_open; then
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

# CRITICAL: Dismiss any remaining dialogs that appeared after document load
# WPS shows "System Check" and "WPS Office default" dialogs after document loads
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
# Take a verification screenshot to confirm document is visible
echo "Taking verification screenshot..."
DISPLAY=:1 scrot /tmp/task_setup_verification.png 2>/dev/null || true

# Final window check - document MUST be visible for task to proceed
final_windows=$(wmctrl -l 2>/dev/null)
if check_document_open; then
    if echo "$final_windows" | grep -qi "License Agreement\|Kingsoft"; then
        echo "WARNING: EULA dialog still visible at task start!"
    else
        echo "SUCCESS: Document window confirmed visible"
    fi
else
    echo "WARNING: Document window not detected in final check"
    echo "Last attempt: trying xdg-open one more time..."
    su - ga -c "DISPLAY=:1 xdg-open /home/ga/Documents/draft_letter.docx" &
    sleep 5
    dismiss_wps_dialogs
    sleep 2
fi

echo "=== Format Business Letter Task Setup Complete ==="
echo ""
echo "Instructions for the agent:"
echo "  1. Add sender address at top: Emily Chen, 425 Pike Street, Seattle, WA 98101"
echo "  2. Add date: January 15, 2024"
echo "  3. Add recipient: Ms. Kathleen Hogan, Chief People Officer, Microsoft Corporation,"
echo "     One Microsoft Way, Redmond, WA 98052"
echo "  4. Add salutation 'Dear Ms. Hogan:' and make it bold"
echo "  5. Set body paragraphs to justified alignment"
echo "  6. Add closing 'Sincerely,' (italic) and signature 'Emily Chen'"
echo "  7. Save the document (Ctrl+S)"
