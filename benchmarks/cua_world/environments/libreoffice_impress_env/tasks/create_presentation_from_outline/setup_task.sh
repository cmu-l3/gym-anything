#!/bin/bash
set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Create Presentation from Outline Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create directories
sudo -u ga mkdir -p /home/ga/Documents/TaskData
sudo -u ga mkdir -p /home/ga/Documents/Presentations

# Clear previous results
rm -f /home/ga/Documents/Presentations/ethics_lecture.odp

# Create the source text file with specific tab indentation for Outline View
cat > /home/ga/Documents/TaskData/ethics_lecture_outline.txt << 'EOF'
Foundations of Moral Philosophy
	Defining Ethics vs. Morality
	Normative Ethics
	Meta-ethics
Utilitarianism
	Jeremy Bentham and John Stuart Mill
	The Greatest Happiness Principle
	Act vs. Rule Utilitarianism
Deontology
	Immanuel Kant
	Categorical Imperative
	Duty-based ethics
Virtue Ethics
	Aristotle and Nicomachean Ethics
	Eudaimonia (Flourishing)
	The Golden Mean
EOF
chown ga:ga /home/ga/Documents/TaskData/ethics_lecture_outline.txt

# Ensure Text Editor (gedit) is available to open the text file easily
if ! dpkg -l | grep -q gedit; then
    echo "Installing gedit for text viewing..."
    apt-get update && apt-get install -y gedit
fi

# Open the text file for the agent so they see the source immediately
echo "Opening source text file..."
su - ga -c "DISPLAY=:1 gedit /home/ga/Documents/TaskData/ethics_lecture_outline.txt &"
sleep 2

# Launch LibreOffice Impress (clean start)
echo "Launching LibreOffice Impress..."
su - ga -c "DISPLAY=:1 libreoffice --impress &"

# Wait for Impress
if wait_for_window "LibreOffice Impress" 30; then
    echo "Impress started successfully"
    # Dismiss "Select a Template" dialog if it appears (Esc usually works)
    safe_xdotool ga :1 key Escape 2>/dev/null || true
    sleep 1
    
    # Focus Impress
    wid=$(get_impress_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid"
        # Maximize
        safe_xdotool ga :1 key F11 2>/dev/null || true
    fi
else
    echo "WARNING: Impress window not found, agent may need to launch it"
fi

# Take initial screenshot
echo "Capturing initial state..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="