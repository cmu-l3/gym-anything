#!/bin/bash
set -e
echo "=== Setting up configure_agent_soundboard task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Vicidial is running
vicidial_ensure_running

# 1. Reset System Settings to DISABLED state
# This ensures the agent must actively enable them to pass.
echo "Resetting system settings..."
docker exec vicidial mysql -ucron -p1234 -D asterisk -e \
    "UPDATE system_settings SET agent_soundboards='0', central_sound_control_active='0';"

# 2. Clean up any previous run artifacts
# Delete the soundboard if it exists
docker exec vicidial mysql -ucron -p1234 -D asterisk -e \
    "DELETE FROM vicidial_soundboards WHERE soundboard_id='LEGAL_SB';"
# Delete the audio link if it exists
docker exec vicidial mysql -ucron -p1234 -D asterisk -e \
    "DELETE FROM vicidial_soundboard_audio WHERE soundboard_id='LEGAL_SB';"
# Clean up audio store entry for this file
docker exec vicidial mysql -ucron -p1234 -D asterisk -e \
    "DELETE FROM vicidial_audio_store WHERE audio_filename='legal_disclosure';"

# Remove the actual audio file from the container if it exists
docker exec vicidial rm -f /var/lib/asterisk/sounds/legal_disclosure.wav 2>/dev/null || true

# 3. Generate the local audio asset for the agent to upload
echo "Generating compliance audio file..."
# Create a valid 8kHz 16-bit Mono WAV file using Python
python3 -c "
import wave, struct, math
with wave.open('/home/ga/Documents/legal_disclosure.wav', 'w') as w:
    w.setparams((1, 2, 8000, 0, 'NONE', 'not compressed'))
    # Generate 1 second of silence/tone
    for i in range(8000):
        value = int(32767.0 * math.sin(2.0 * math.pi * 440.0 * i / 8000.0))
        w.writeframes(struct.pack('<h', value))
"
chown ga:ga /home/ga/Documents/legal_disclosure.wav
chmod 644 /home/ga/Documents/legal_disclosure.wav

# 4. Prepare Browser
# Kill any existing firefox
pkill -f firefox 2>/dev/null || true

# Start Firefox at Admin Login
su - ga -c "DISPLAY=:1 firefox '${VICIDIAL_ADMIN_URL}' > /tmp/firefox_vicidial.log 2>&1 &"

# Wait for window and maximize
wait_for_window "Firefox"
maximize_active_window

# Record initial state screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="