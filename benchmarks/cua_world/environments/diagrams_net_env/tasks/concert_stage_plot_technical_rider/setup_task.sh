#!/bin/bash
set -e

echo "=== Setting up Concert Stage Plot Task ==="

# 1. Create Directories
mkdir -p /home/ga/Desktop
mkdir -p /home/ga/Diagrams
chown -R ga:ga /home/ga/Desktop /home/ga/Diagrams

# 2. Create the Technical Specification File
cat > /home/ga/Desktop/neon_velvet_tech_spec.txt << 'EOF'
ARTIST: NEON VELVET
DATE: 2024 TOUR
CONTACT: Sarah Jenkins (PM) - 555-0199

STAGE PLOT & INPUT LIST REQUIREMENTS

LINEUP & POSITIONING:
1. DRUMS: Upstage Center. Standard 5-piece kit. 8x8 Carpet. 
   Needs: 1 Drum Fill (Sub + Top) on Left side of drummer. AC Power.
2. BASS GUITAR: Stage Right (Audience Left).
   Gear: Ampeg SVT Head + 8x10 Cab.
   Needs: 1 Monitor Wedge. AC Power.
3. KEYS: Stage Right (Audience Left), positioned Downstage of Bass.
   Gear: Nord Stage 3.
   Needs: 1 Monitor Wedge. AC Power. Stereo DI.
4. GUITAR: Stage Left (Audience Right).
   Gear: Fender Twin Reverb.
   Needs: 1 Monitor Wedge. AC Power. Mic for Amp.
5. LEAD VOCALS: Downstage Center.
   Needs: 2 Monitor Wedges (Stereo pair). Straight Mic Stand. Wireless Mic.

INPUT LIST PREFERENCES:
CH  INSTRUMENT       MIC/DI
01  Kick In          Beta 91
02  Kick Out         Beta 52
03  Snare Top        SM57
04  Snare Bottom     SM57
05  Hi-Hat           SM81
06  Rack Tom         e604
07  Floor Tom        e604
08  Overhead L       C414
09  Overhead R       C414
10  Bass DI          XLR from Head
11  Bass Mic         RE20
12  Guitar Amp       e609
13  Keys L           DI
14  Keys R           DI
15  Lead Vocal       Wireless (Shure Axient)
16  Spare Vocal      SM58
EOF

chown ga:ga /home/ga/Desktop/neon_velvet_tech_spec.txt
chmod 644 /home/ga/Desktop/neon_velvet_tech_spec.txt

# 3. Clean up previous results
rm -f /home/ga/Diagrams/neon_velvet_rider.drawio
rm -f /home/ga/Diagrams/neon_velvet_rider.pdf

# 4. Record Start Time
date +%s > /tmp/task_start_time.txt

# 5. Launch Diagrams.net (draw.io)
echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 /opt/drawio/drawio.AppImage --no-sandbox > /tmp/drawio_launch.log 2>&1 &"

# 6. Wait for window and handle update dialog
echo "Waiting for draw.io window..."
for i in $(seq 1 30); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "draw.io"; then
        echo "draw.io window detected."
        break
    fi
    sleep 1
done

sleep 5

# Aggressively dismiss update dialog if it appears
echo "Checking for update dialog..."
for i in $(seq 1 10); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qiE "update|confirm"; then
        echo "Dismissing dialog..."
        DISPLAY=:1 xdotool key Escape
        sleep 0.5
    fi
done

# Focus the window
DISPLAY=:1 wmctrl -a "draw.io" 2>/dev/null || true

# 7. Take Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="