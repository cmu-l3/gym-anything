#!/bin/bash
set -e
echo "=== Setting up add_facility_logo_badge task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# ============================================================
# 1. Create the Company Logo
# ============================================================
echo "Creating company logo file..."
mkdir -p /home/ga/Desktop

# Generate a professional-looking logo using ImageMagick
# We use a generated one to ensure it looks exactly as expected for VLM verification
convert -size 200x200 xc:white \
    -fill '#1a5276' -draw "roundrectangle 10,10 190,190 15,15" \
    -fill white -font Helvetica-Bold -pointsize 36 \
    -gravity North -annotate +0+35 "ACME" \
    -fill '#d4e6f1' -font Helvetica -pointsize 18 \
    -gravity Center -annotate +0+10 "CONSULTING" \
    -fill '#f39c12' -draw "circle 100,130 100,155" \
    -fill white -font Helvetica-Bold -pointsize 14 \
    -gravity South -annotate +0+30 "EST. 2019" \
    /home/ga/Desktop/company_logo.png 2>/dev/null || \
# Fallback if font missing
convert -size 200x200 xc:'#1a5276' \
    -fill white -pointsize 40 \
    -gravity Center -annotate +0-15 "ACME" \
    -fill '#f39c12' -pointsize 20 \
    -gravity Center -annotate +0+25 "Corp" \
    /home/ga/Desktop/company_logo.png

chmod 644 /home/ga/Desktop/company_logo.png
chown ga:ga /home/ga/Desktop/company_logo.png

echo "Logo created at /home/ga/Desktop/company_logo.png"

# ============================================================
# 2. Record Initial State of Badge Files
# ============================================================
echo "Recording initial badge template state..."
# Look for badge templates in common locations
BADGE_DIRS=(
    "/home/ga/.wine/drive_c/Program Files/Jolly Technologies/Lobby Track"
    "/home/ga/.wine/drive_c/ProgramData/Jolly Technologies/Lobby Track"
    "/home/ga/LobbyTrack"
)

rm -f /tmp/initial_badge_state.txt
for dir in "${BADGE_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        find "$dir" -type f \( -name "*.badge" -o -name "*.btp" -o -name "*.xml" -o -name "*.mdb" \) -printf "%p %T@\n" >> /tmp/initial_badge_state.txt 2>/dev/null || true
    fi
done

# ============================================================
# 3. Launch Application
# ============================================================
ensure_lobbytrack_running

# Wait for UI to stabilize
sleep 5

# ============================================================
# 4. Capture Initial Evidence
# ============================================================
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="