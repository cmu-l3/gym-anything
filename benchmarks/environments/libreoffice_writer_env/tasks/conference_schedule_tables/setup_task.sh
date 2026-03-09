#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up Conference Schedule Task ==="

# 1. Create the source data file
mkdir -p /home/ga/Documents
cat > /home/ga/Documents/schedule_data.txt << 'EOF'
TIME | EVENT DETAILS
08:00 - 09:00 | Registration & Breakfast (ALL ATTENDEES)
09:00 - 10:30 | Opening Keynote: The Future of AI (ALL ATTENDEES)
10:30 - 10:45 | Coffee Break (ALL ATTENDEES)
10:45 - 12:00 | [Main Stage] Panel: Ethics in Tech | [Track A] Workshop: Python Basics | [Track B] Workshop: Cloud Security
12:00 - 13:30 | Networking Lunch (ALL ATTENDEES)
13:30 - 15:00 | [Main Stage] Product Reveal | [Track A] Coding Challenge | [Track B] CTO Roundtable
15:00 - 15:15 | Afternoon Tea (ALL ATTENDEES)
15:15 - 16:30 | Closing Keynote: Building Resilience (ALL ATTENDEES)
16:30 - 18:00 | Networking Mixer (ALL ATTENDEES)
EOF

chown ga:ga /home/ga/Documents/schedule_data.txt
chmod 644 /home/ga/Documents/schedule_data.txt

# 2. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Clean up previous results
rm -f /home/ga/Documents/conference_schedule.docx 2>/dev/null || true

# 4. Start LibreOffice Writer (Blank)
if ! pgrep -f "soffice.bin" > /dev/null; then
    echo "Starting LibreOffice Writer..."
    su - ga -c "DISPLAY=:1 libreoffice --writer --norestore &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "Writer"; then
            break
        fi
        sleep 1
    done
fi

# 5. Focus and Maximize
WID=$(get_writer_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz
fi

# 6. Open the text file in a separate text editor (gedit) so agent can read it
#    Use background process so it doesn't block
if ! pgrep -f "gedit" > /dev/null; then
    su - ga -c "DISPLAY=:1 gedit /home/ga/Documents/schedule_data.txt &"
fi

# 7. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="