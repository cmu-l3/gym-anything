#!/bin/bash
set -e
echo "=== Setting up setup_seasonal_moh task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure Vicidial is running
vicidial_ensure_running

# 2. Cleanup: Remove existing MOH entry if it exists (for idempotency/clean state)
echo "Cleaning up previous state..."
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "DELETE FROM vicidial_music_on_hold WHERE moh_id='HOLIDAY25';" 2>/dev/null || true
docker exec vicidial rm -rf /var/lib/asterisk/mohmp3/HOLIDAY25 2>/dev/null || true

# Record initial count (should be 0 for this ID)
INITIAL_COUNT=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e "SELECT count(*) FROM vicidial_music_on_hold WHERE moh_id='HOLIDAY25'" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_moh_count.txt

# 3. Prepare Audio Data
# Vicidial requires specific WAV format (PCM 16bit 8kHz Mono).
# We generate valid dummy WAV files to ensure upload success.
echo "Generating audio assets..."
mkdir -p /home/ga/Documents/Audio

cat << 'PYTHON_EOF' > /tmp/gen_wav.py
import wave, struct, math, sys, os

def create_tone(filename, freq, duration=1):
    try:
        with wave.open(filename, 'w') as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(8000)
            frames = int(8000 * duration)
            for i in range(frames):
                # Generate sine wave
                value = int(32767.0 * math.sin(2 * math.pi * freq * i / 8000.0))
                w.writeframes(struct.pack('<h', value))
        print(f"Created {filename}")
    except Exception as e:
        print(f"Error creating {filename}: {e}")

create_tone('/home/ga/Documents/Audio/holiday_jingle.wav', 440, 2)    # A4 tone
create_tone('/home/ga/Documents/Audio/seasonal_offer.wav', 523, 2.5)  # C5 tone
PYTHON_EOF

python3 /tmp/gen_wav.py
rm /tmp/gen_wav.py
chown -R ga:ga /home/ga/Documents/Audio

# 4. Launch Firefox to Admin Page
echo "Launching Firefox..."
VICIDIAL_ADMIN_URL="http://localhost/vicidial/admin.php"

if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '$VICIDIAL_ADMIN_URL' > /tmp/firefox.log 2>&1 &"
else
    # If running, open new tab/window
    su - ga -c "DISPLAY=:1 firefox -new-window '$VICIDIAL_ADMIN_URL' &"
fi

# Wait for window
wait_for_window "firefox\|mozilla\|vicidial" 60

# Maximize and Focus
focus_firefox
maximize_active_window

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="