#!/bin/bash
set -euo pipefail

echo "=== Setting up Configure Anti-Phishing Display Task ==="

source /workspace/scripts/task_utils.sh || true

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

TB_PROFILE="/home/ga/.thunderbird/default-release"
USER_JS="$TB_PROFILE/user.js"
PREFS_JS="$TB_PROFILE/prefs.js"

# 1. Close any running instances of Thunderbird to allow modifying prefs
echo "Ensuring Thunderbird is closed before modifying preferences..."
su - ga -c "DISPLAY=:1 wmctrl -c 'Thunderbird'" 2>/dev/null || true
sleep 2
pkill -f "thunderbird" 2>/dev/null || true
sleep 1

# 2. Un-lock any preferences that might be enforced via user.js
# user.js overrides prefs.js on every startup, so we must remove these keys
if [ -f "$USER_JS" ]; then
    sed -i '/mailnews.display.html_as/d' "$USER_JS" 2>/dev/null || true
    sed -i '/mail.show_headers/d' "$USER_JS" 2>/dev/null || true
    sed -i '/mail.showCondensedAddresses/d' "$USER_JS" 2>/dev/null || true
    sed -i '/mailnews.message_display.disable_remote_image/d' "$USER_JS" 2>/dev/null || true
    sed -i '/browser.display.use_document_fonts/d' "$USER_JS" 2>/dev/null || true
fi

# 3. Inject insecure/default starting state into prefs.js
# The agent will have to correct these.
echo "Injecting initial insecure defaults..."
mkdir -p "$TB_PROFILE"
cat >> "$PREFS_JS" << 'EOF'
user_pref("mailnews.display.html_as", 0);
user_pref("mail.show_headers", 1);
user_pref("mail.showCondensedAddresses", true);
user_pref("mailnews.message_display.disable_remote_image", false);
user_pref("browser.display.use_document_fonts", 1);
EOF
chown -R ga:ga /home/ga/.thunderbird

# 4. Start Thunderbird
echo "Starting Thunderbird..."
su - ga -c "DISPLAY=:1 thunderbird -profile $TB_PROFILE &" 2>/dev/null

# Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Mozilla Thunderbird"; then
        echo "Thunderbird window detected"
        break
    fi
    sleep 1
done

# 5. Maximize and focus
sleep 2
DISPLAY=:1 wmctrl -r "Mozilla Thunderbird" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Mozilla Thunderbird" 2>/dev/null || true

# Select inbox
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true

# 6. Take initial screenshot
echo "Capturing initial state..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="