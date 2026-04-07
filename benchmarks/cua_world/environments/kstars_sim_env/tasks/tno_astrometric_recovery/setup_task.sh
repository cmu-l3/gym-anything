#!/bin/bash
set -e
echo "=== Setting up tno_astrometric_recovery task ==="

source /workspace/scripts/task_utils.sh

# ── 1. Record task start time (anti-gaming) ───────────────────────────
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# ── 2. Clean up previous artifacts ────────────────────────────────────
rm -rf /home/ga/Images/tno_recovery
rm -f /home/ga/Documents/tno_ephemeris_2026.txt
rm -f /home/ga/Documents/tno_recovery_report.txt
rm -f /tmp/task_result.json

# ── 3. Create required directory structure ────────────────────────────
mkdir -p /home/ga/Images/tno_recovery/Eris
mkdir -p /home/ga/Images/tno_recovery/Makemake
mkdir -p /home/ga/Images/tno_recovery/Haumea
mkdir -p /home/ga/Documents

# ── 4. ERROR INJECTION: Stale decoy files for Eris ────────────────────
# Agent must not count these or think the job is already done
# We give them timestamps far in the past (Jan 1, 2025)
touch -t 202501010000 /home/ga/Images/tno_recovery/Eris/decoy_eris_001.fits
touch -t 202501010000 /home/ga/Images/tno_recovery/Eris/decoy_eris_002.fits
touch -t 202501010000 /home/ga/Images/tno_recovery/Eris/decoy_eris_003.fits

chown -R ga:ga /home/ga/Images/tno_recovery
chown -R ga:ga /home/ga/Documents

# ── 5. Ensure INDI server is running with simulators ──────────────────
ensure_indi_running
sleep 2
connect_all_devices

# ── 6. Configure filter wheel slots ───────────────────────────────────
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_1=Luminance" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_2=Red" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_3=Green" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_4=Blue" 2>/dev/null || true
sleep 1

# ── 7. Park telescope (Agent will start from a neutral position) ──────
park_telescope
sleep 1

# ── 8. Reset CCD upload directory ─────────────────────────────────────
set_ccd_upload_dir "/home/ga/Images/captures"
indi_setprop "CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On" 2>/dev/null || true

# ── 9. Create the Ephemeris Document ──────────────────────────────────
cat > /home/ga/Documents/tno_ephemeris_2026.txt << 'EOF'
MINOR PLANET CENTER - EPHEMERIS SERVICE
=======================================
Observation Context: Dwarf Planet Astrometric Recovery

Target: Eris (136199)
Date       RA (J2000)   Dec (J2000)  Mag
2026-02-10 01 52 10.0  -03 05 00    18.7
2026-03-10 01 51 12.0  -03 10 30    18.7
2026-04-10 01 50 15.0  -03 15 00    18.7

Target: Makemake (136472)
Date       RA (J2000)   Dec (J2000)  Mag
2026-02-10 13 29 15.0  +25 50 10    17.0
2026-03-10 13 28 04.0  +25 55 30    16.9
2026-04-10 13 26 50.0  +26 01 00    17.0

Target: Haumea (136108)
Date       RA (J2000)   Dec (J2000)  Mag
2026-02-10 14 56 30.0  +14 10 00    17.3
2026-03-10 14 55 20.0  +14 15 10    17.3
2026-04-10 14 54 10.0  +14 20 20    17.4

Notes:
- Filter requirements: Clear/Luminance (Slot 1)
- Deep exposures required (120s minimum)
- Separate subdirectories per target
EOF

chown ga:ga /home/ga/Documents/tno_ephemeris_2026.txt

# ── 10. Ensure KStars is running and maximized ────────────────────────
ensure_kstars_running
sleep 3

for i in 1 2 3; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
done

maximize_kstars
focus_kstars
sleep 1

# ── 11. Take initial screenshot ───────────────────────────────────────
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Ephemeris at: ~/Documents/tno_ephemeris_2026.txt"
echo "Telescope parked. Ready for observation."