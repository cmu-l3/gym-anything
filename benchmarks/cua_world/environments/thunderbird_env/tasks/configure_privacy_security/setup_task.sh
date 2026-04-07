#!/bin/bash
echo "=== Setting up configure_privacy_security task ==="

source /workspace/scripts/task_utils.sh || true

# Record task start time
date +%s > /tmp/task_start_time.txt

PROFILE_DIR="/home/ga/.thunderbird/default-release"
PREFS_FILE="${PROFILE_DIR}/prefs.js"

# Close Thunderbird if it's currently running to safely edit prefs
echo "Ensuring Thunderbird is closed before modifying settings..."
if pgrep -f "thunderbird" > /dev/null 2>&1; then
    su - ga -c "DISPLAY=:1 wmctrl -c 'Thunderbird'" 2>/dev/null || true
    sleep 2
    pkill -f "thunderbird" 2>/dev/null || true
    sleep 1
fi

# Inject insecure default settings to ensure a known-bad starting state
echo "Injecting insecure defaults into prefs.js..."

# Ensure the profile and prefs.js exist
sudo -u ga mkdir -p "$PROFILE_DIR"
sudo -u ga touch "$PREFS_FILE"

# Remove existing target preferences to avoid duplicates
sed -i '/mailnews.message_display.disable_remote_image/d' "$PREFS_FILE" 2>/dev/null || true
sed -i '/mailnews.display.prefer_plaintext/d' "$PREFS_FILE" 2>/dev/null || true
sed -i '/mailnews.display.html_as/d' "$PREFS_FILE" 2>/dev/null || true
sed -i '/mail.phishing.detection.enabled/d' "$PREFS_FILE" 2>/dev/null || true
sed -i '/mail.mdn.report.not_in_to_cc/d' "$PREFS_FILE" 2>/dev/null || true
sed -i '/mail.mdn.report.outside_domain/d' "$PREFS_FILE" 2>/dev/null || true
sed -i '/mail.mdn.report.other/d' "$PREFS_FILE" 2>/dev/null || true
sed -i '/privacy.donottrackheader.enabled/d' "$PREFS_FILE" 2>/dev/null || true

# Append the insecure defaults
cat >> "$PREFS_FILE" << 'EOF'
user_pref("mailnews.message_display.disable_remote_image", false);
user_pref("mailnews.display.prefer_plaintext", false);
user_pref("mailnews.display.html_as", 0);
user_pref("mail.phishing.detection.enabled", false);
user_pref("mail.mdn.report.not_in_to_cc", 1);
user_pref("mail.mdn.report.outside_domain", 1);
user_pref("mail.mdn.report.other", 1);
user_pref("privacy.donottrackheader.enabled", false);
EOF

chown ga:ga "$PREFS_FILE"

# Record the initial modification time of prefs.js
stat -c %Y "$PREFS_FILE" > /tmp/initial_prefs_mtime.txt 2>/dev/null || echo "0" > /tmp/initial_prefs_mtime.txt

# Start Thunderbird
echo "Starting Thunderbird with insecure configuration..."
su - ga -c "DISPLAY=:1 thunderbird -profile /home/ga/.thunderbird/default-release &" 2>/dev/null
sleep 6

# Focus and maximize window
WID=$(su - ga -c "DISPLAY=:1 wmctrl -l 2>/dev/null" | grep -i "Mozilla Thunderbird" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -i -r '$WID' -b add,maximized_vert,maximized_horz" 2>/dev/null || true
    su - ga -c "DISPLAY=:1 wmctrl -i -a '$WID'" 2>/dev/null || true
fi

# Select desktop and re-focus to ensure top level
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1
if [ -n "$WID" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -i -a '$WID'" 2>/dev/null || true
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="