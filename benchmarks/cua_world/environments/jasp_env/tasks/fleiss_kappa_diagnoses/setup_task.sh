#!/bin/bash
set -e
echo "=== Setting up Fleiss' Kappa Reliability task ==="

# 1. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 2. Prepare Data Directory
mkdir -p /home/ga/Documents/JASP
chown -R ga:ga /home/ga/Documents/JASP

# 3. Download Real Dataset (Psychiatric Diagnoses)
DATA_URL="https://raw.githubusercontent.com/vincentarelbundock/Rdatasets/master/csv/irr/diagnoses.csv"
DEST_FILE="/home/ga/Documents/JASP/diagnoses.csv"

echo "Downloading dataset..."
if curl -L -o "$DEST_FILE" "$DATA_URL" --max-time 10; then
    echo "Download successful."
else
    echo "WARNING: Download failed, generating fallback dataset."
    # Fallback: Generate a subset of the Fleiss data if network fails
    cat << 'EOF' > "$DEST_FILE"
"","rater1","rater2","rater3","rater4","rater5","rater6"
"1","Depression","Depression","Depression","Depression","Depression","Depression"
"2","Depression","Depression","Depression","Depression","Depression","Depression"
"3","Depression","Depression","Depression","Depression","Depression","Depression"
"4","Depression","Depression","Depression","Depression","Depression","Depression"
"5","Depression","Depression","Depression","Depression","Depression","Depression"
"6","Depression","Depression","Depression","Depression","Depression","Depression"
"7","Personality Disorder","Personality Disorder","Personality Disorder","Personality Disorder","Personality Disorder","Personality Disorder"
"8","Personality Disorder","Personality Disorder","Personality Disorder","Personality Disorder","Personality Disorder","Personality Disorder"
"9","Personality Disorder","Personality Disorder","Personality Disorder","Personality Disorder","Personality Disorder","Personality Disorder"
"10","Personality Disorder","Personality Disorder","Personality Disorder","Personality Disorder","Personality Disorder","Personality Disorder"
"11","Schizophrenia","Schizophrenia","Schizophrenia","Schizophrenia","Schizophrenia","Schizophrenia"
"12","Schizophrenia","Schizophrenia","Schizophrenia","Schizophrenia","Schizophrenia","Schizophrenia"
"13","Schizophrenia","Schizophrenia","Schizophrenia","Schizophrenia","Schizophrenia","Schizophrenia"
"14","Schizophrenia","Schizophrenia","Schizophrenia","Schizophrenia","Schizophrenia","Schizophrenia"
"15","Neurosis","Neurosis","Neurosis","Neurosis","Neurosis","Neurosis"
"16","Neurosis","Neurosis","Neurosis","Neurosis","Neurosis","Neurosis"
"17","Neurosis","Neurosis","Neurosis","Neurosis","Neurosis","Neurosis"
"18","Other","Other","Other","Other","Other","Other"
"19","Other","Other","Other","Other","Other","Other"
"20","Other","Other","Other","Other","Other","Other"
"21","Depression","Depression","Depression","Depression","Depression","Personality Disorder"
"22","Depression","Depression","Depression","Depression","Personality Disorder","Personality Disorder"
"23","Depression","Depression","Depression","Personality Disorder","Personality Disorder","Personality Disorder"
"24","Depression","Depression","Personality Disorder","Personality Disorder","Personality Disorder","Personality Disorder"
"25","Depression","Personality Disorder","Personality Disorder","Personality Disorder","Personality Disorder","Personality Disorder"
"26","Neurosis","Neurosis","Neurosis","Neurosis","Neurosis","Schizophrenia"
"27","Neurosis","Neurosis","Neurosis","Neurosis","Schizophrenia","Schizophrenia"
"28","Neurosis","Neurosis","Neurosis","Schizophrenia","Schizophrenia","Schizophrenia"
"29","Neurosis","Neurosis","Schizophrenia","Schizophrenia","Schizophrenia","Schizophrenia"
"30","Neurosis","Schizophrenia","Schizophrenia","Schizophrenia","Schizophrenia","Schizophrenia"
EOF
fi

# Ensure permissions
chown ga:ga "$DEST_FILE"
chmod 644 "$DEST_FILE"

# 4. Start JASP
echo "Starting JASP..."
# Kill any existing instances
pkill -f "org.jaspstats.JASP" 2>/dev/null || true

# Launch using the wrapper that handles flatpak flags
su - ga -c "setsid /usr/local/bin/launch-jasp > /tmp/jasp_launch.log 2>&1 &"

# 5. Wait for window and setup UI
echo "Waiting for JASP window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JASP"; then
        echo "JASP window found."
        break
    fi
    sleep 1
done

# Short wait for UI to render
sleep 5

# Maximize window
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
# Focus window
DISPLAY=:1 wmctrl -a "JASP" 2>/dev/null || true

# Dismiss any startup dialogs (Esc key)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# 6. Capture initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="