#!/bin/bash
set -e
echo "=== Setting up frb_host_galaxy_characterization task ==="

source /workspace/scripts/task_utils.sh

# ── 1. Record task start time ─────────────────────────────────────────
date +%s > /tmp/task_start_time.txt

# ── 2. Clean up previous artifacts ────────────────────────────────────
rm -rf /home/ga/Images/FRB2024exq
rm -rf /home/ga/Documents/telegrams
rm -f /home/ga/Documents/frb_optical_status.txt
rm -f /tmp/task_result.json

# ── 3. Create necessary directories ───────────────────────────────────
mkdir -p /home/ga/Documents/telegrams
mkdir -p /home/ga/Images/FRB2024exq

# ── 4. ERROR INJECTION: Pre-seed a stale finding chart ────────────────
# This tests if the agent actually generates a NEW finding chart
touch -t 202301010000 /home/ga/Images/FRB2024exq/finding_chart_cool.png
echo "dummy" > /home/ga/Images/FRB2024exq/finding_chart_cool.png

chown -R ga:ga /home/ga/Images/FRB2024exq
chown -R ga:ga /home/ga/Documents

# ── 5. Start INDI and simulators ──────────────────────────────────────
ensure_indi_running
sleep 2
connect_all_devices

# ── 6. Configure filter wheel ─────────────────────────────────────────
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_1=Luminance" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_2=V" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_3=B" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_4=R" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_5=Ha" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_6=OIII" 2>/dev/null || true
sleep 1

# ── 7. Unpark telescope and slew to NCP ───────────────────────────────
unpark_telescope
sleep 1
# Slew to North Celestial Pole (RA 0h, Dec 89.9d) to ensure they must slew
slew_to_coordinates 0.0 89.9
wait_for_slew_complete 20

# ── 8. Reset CCD upload dir to a safe default ─────────────────────────
set_ccd_upload_dir "/home/ga/Images/captures"
indi_setprop "CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On" 2>/dev/null || true

# ── 9. Write the decoy and real ATel documents ────────────────────────
cat > /home/ga/Documents/telegrams/ATel_16001.txt << 'EOF'
[ Astronomer's Telegram ]
ATel #16001; X. Chen et al.
Subject: Radio flaring from galactic microquasar GRS 1915+105
Date: Current

We report intense radio flaring from the well-known galactic microquasar
GRS 1915+105. Observations with the VLA at 8.4 GHz show flux densities
exceeding 200 mJy.

Coordinates (J2000):
RA: 19h 15m 11.6s
Dec: +10d 56m 44s

Optical and X-ray follow-up is encouraged, though high local extinction
may limit optical visibility.
EOF

cat > /home/ga/Documents/telegrams/ATel_16002.txt << 'EOF'
[ Astronomer's Telegram ]
ATel #16002; M. Smith et al.
Subject: Precise localization of repeating FRB 2024exq
Date: Current

We report the precise interferometric localization of the recently
discovered repeating Fast Radio Burst, FRB 2024exq. Using the upgraded
GMRT, we detected 3 consecutive bursts from this source, allowing for
sub-arcsecond localization.

The precise coordinates (J2000) are:
R.A. = 05h 31m 58.7s
Decl. = +33d 08m 52.5s

The localized position lies on the outskirts of a faint, blue
star-forming galaxy (r ~ 22.4 mag). Deep optical imaging (L, R, Ha)
is urgently requested to characterize the host galaxy and local
star formation environment.
EOF

chown ga:ga /home/ga/Documents/telegrams/ATel_*.txt

# ── 10. Ensure KStars is running and maximized ────────────────────────
ensure_kstars_running
sleep 3
for i in 1 2; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
done
maximize_kstars
focus_kstars
sleep 1

# ── 11. Record initial screenshot ─────────────────────────────────────
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="