#!/bin/bash
set -euo pipefail

echo "=== Setting up FOMC Client Briefing Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

cleanup_temp_files
kill_onlyoffice ga
sleep 1

# Create required directories
sudo -u ga mkdir -p "/home/ga/Documents/TextDocuments"
sudo -u ga mkdir -p "/home/ga/Documents/Spreadsheets"

# Create the raw text file (FOMC Minutes Excerpt)
cat > "/home/ga/Documents/TextDocuments/FOMC_Minutes_Raw.txt" << 'EOF'
Recent indicators suggest that economic activity has been expanding at a solid pace. Job gains have moderated since earlier in the year but remain strong, and the unemployment rate has remained low. Inflation has eased over the past year but remains elevated.

Staff Economic Outlook
The economic projection prepared by the staff for the December FOMC meeting was somewhat stronger than the October forecast. Real GDP growth was expected to step down.

Participants' Views on Current Conditions
In their discussion of current economic conditions, participants noted that recent indicators suggest that economic activity has been expanding at a solid pace.
EOF
chown ga:ga "/home/ga/Documents/TextDocuments/FOMC_Minutes_Raw.txt"

# Create the CSV file (SEP Projections)
cat > "/home/ga/Documents/Spreadsheets/SEP_Projections.csv" << 'EOF'
Variable,2023,2024,2025,2026,Longer run
Change in real GDP,2.6,1.4,1.8,1.9,1.8
Unemployment rate,3.8,4.1,4.1,4.1,4.1
PCE inflation,2.8,2.4,2.1,2.0,2.0
Core PCE inflation,3.2,2.4,2.2,2.0,-
EOF
chown ga:ga "/home/ga/Documents/Spreadsheets/SEP_Projections.csv"

# Remove any existing output from previous runs
rm -f "/home/ga/Documents/TextDocuments/FOMC_Client_Briefing.docx"

# Launch ONLYOFFICE Document Editor
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors --new:word > /tmp/onlyoffice.log 2>&1 &"

# Wait for window to appear
wait_for_window "ONLYOFFICE" 30

# Maximize and focus ONLYOFFICE window
WID=$(get_onlyoffice_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi
sleep 2

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="