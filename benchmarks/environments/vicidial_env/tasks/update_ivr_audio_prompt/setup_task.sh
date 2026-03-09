#!/bin/bash
set -e
echo "=== Setting up Update IVR Audio Prompt task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Prepare the "Real" Audio Data
# We use a standard Asterisk sound file to ensure valid format (16bit 8k PCM WAV)
AUDIO_URL="https://raw.githubusercontent.com/asterisk/asterisk-sounds/master/sounds/en/demo-congrats.wav"
TARGET_FILE="/home/ga/Documents/holiday_greeting_2026.wav"

echo "Downloading sample audio file..."
# Use curl or wget; ensure it exists
if ! wget -q -O "$TARGET_FILE" "$AUDIO_URL"; then
    echo "Network download failed, creating dummy WAV header..."
    # Minimal WAV header creation if network fails (fallback)
    echo -n -e "\x52\x49\x46\x46\x24\x00\x00\x00\x57\x41\x56\x45\x66\x6d\x74\x20\x10\x00\x00\x00\x01\x00\x01\x00\x44\xac\x00\x00\x88\x58\x01\x00\x02\x00\x10\x00\x64\x61\x74\x61\x00\x00\x00\x00" > "$TARGET_FILE"
fi
chown ga:ga "$TARGET_FILE"
chmod 644 "$TARGET_FILE"

# 2. Setup Initial Database State
# Ensure the 'MAIN_IVR' call menu exists with a DEFAULT prompt
echo "Injecting MAIN_IVR into database..."
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "
DELETE FROM vicidial_call_menu WHERE menu_id='MAIN_IVR';
INSERT INTO vicidial_call_menu 
(menu_id, menu_name, menu_prompt, menu_timeout, menu_timeout_prompt, menu_invalid_prompt, menu_repeat, menu_time_check, call_time_id, track_in_vdac, custom_dialplan_entry, user_group) 
VALUES 
('MAIN_IVR', 'Main Inbound Menu', 'default_greeting', '10', 'default_timeout', 'default_invalid', '0', '0', '', '0', '0', '---ALL---');
"

# 3. Ensure User Permissions
# Update user 6666 to have permission to modify call menus and access audio store
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "
UPDATE vicidial_users 
SET modify_call_menu='1', ast_admin_access='1' 
WHERE user='6666';
"

# 4. Clean up any previous run artifacts
# Remove the file from the container if it exists from a previous run to prevent 'do nothing' success
echo "Cleaning up container audio store..."
docker exec vicidial rm -f /var/lib/asterisk/sounds/holiday_greeting_2026.wav 2>/dev/null || true
docker exec vicidial rm -f /var/lib/asterisk/sounds/holiday_greeting_2026.gsm 2>/dev/null || true
docker exec vicidial rm -f /var/lib/asterisk/sounds/holiday_greeting_2026.sln 2>/dev/null || true

# 5. Launch Firefox and prep window
# Vicidial URL
VICIDIAL_URL="${VICIDIAL_ADMIN_URL:-http://localhost/vicidial/admin.php}"

if ! pgrep -f "firefox" > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$VICIDIAL_URL' > /dev/null 2>&1 &"
else
    # Navigate if already open
    navigate_to_url "$VICIDIAL_URL"
fi

# Wait for window
wait_for_window "firefox\|mozilla\|vicidial" 30

# Maximize and focus
focus_firefox
maximize_active_window

# Record initial db state for anti-gaming
INITIAL_PROMPT=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e "SELECT menu_prompt FROM vicidial_call_menu WHERE menu_id='MAIN_IVR'")
echo "$INITIAL_PROMPT" > /tmp/initial_prompt.txt

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="