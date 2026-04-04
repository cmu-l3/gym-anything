#!/bin/bash
set -e
echo "=== Setting up Event Badge Mail Merge Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Documents directory exists
sudo -u ga mkdir -p /home/ga/Documents

# 1. Create the Data Source (CSV)
# Realistically formatted CSV for mail merge
cat > /home/ga/Documents/attendees.csv << 'CSVEOF'
First Name,Last Name,Organization,Role
Sarah,Chen,BioTech Inc.,Speaker
Michael,Ross,Pearson Legal,Attendee
Jessica,Wong,City Planning,Panelist
David,Miller,StartUp Hub,Exhibitor
Amanda,Johnson,Civic Data,Attendee
Robert,Smith,Open Gov Foundation,Speaker
Jennifer,Wu,Tech for Good,Attendee
James,Wilson,Policy Institute,Moderator
Linda,Martinez,Community Action,Attendee
William,Taylor,Urban Design Co.,Exhibitor
Elizabeth,Anderson,Digital Rights Grp,Panelist
Richard,Thomas,Future Cities,Attendee
Barbara,Hernandez,Innovation Lab,Attendee
Susan,Moore,Smart Transit,Speaker
Joseph,Martin,Green Energy Corp,Attendee
Thomas,Jackson,Public Works,Attendee
Charles,White,Data Alliance,Exhibitor
Christopher,Lee,Code for America,Panelist
Daniel,Thompson,City Council,VIP
Matthew,Garcia,Mayor's Office,VIP
Anthony,Martinez,Regional Plan Assoc,Attendee
Mark,Robinson,Transit Authority,Attendee
Donald,Clark,Housing Dept,Attendee
Steven,Rodriguez,Education Board,Attendee
CSVEOF

# Set permissions
chown ga:ga /home/ga/Documents/attendees.csv
chmod 644 /home/ga/Documents/attendees.csv

# 2. Clean up any previous run artifacts
rm -f /home/ga/Documents/badges_merged.odt
rm -f /home/ga/Documents/badges_merged.docx

# 3. Launch LibreOffice Writer
echo "Launching LibreOffice Writer..."
# We launch generic writer; the user must navigate to File > New > Labels
su - ga -c "DISPLAY=:1 libreoffice --writer --norestore > /tmp/writer_launch.log 2>&1 &"

# 4. Wait for window and maximize
wait_for_window "LibreOffice Writer" 60
sleep 2

WID=$(get_writer_window_id)
if [ -n "$WID" ]; then
    echo "Maximizing Writer window ($WID)..."
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Dismiss any "What's New" or recovery dialogs
safe_xdotool ga :1 key Escape
sleep 0.5

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="
echo "Data source created at: /home/ga/Documents/attendees.csv"
echo "Ready for Mail Merge task."