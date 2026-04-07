#!/bin/bash
set -e
echo "=== Setting up exoplanet_transit_photometry task ==="

source /workspace/scripts/task_utils.sh

# ── 1. Record task start time ─────────────────────────────────────────
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# ── 2. Clean up previous artifacts ────────────────────────────────────
rm -rf /home/ga/Images/transits
rm -f /home/ga/Documents/transit_prediction.txt
rm -f /home/ga/Documents/transit_log.txt
rm -f /tmp/task_result.json

# ── 3. Create output directory structure ──────────────────────────────
mkdir -p /home/ga/Images/transits/hd189733b
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Images/transits
chown -R ga:ga /home/ga/Documents

# ── 4. Ensure INDI server is running with all simulators ──────────────
ensure_indi_running
sleep 2
connect_all_devices

# ── 5. Configure filter wheel ─────────────────────────────────────────
indi_setprop "Filter Simulator.FILTER_NAME.FILTER_SLOT_NAME_1=Luminance" 2>/dev/null || true
indi_setprop "Filter Simulator.FILTER_NAME.FILTER_SLOT_NAME_2=V" 2>/dev/null || true
indi_setprop "Filter Simulator.FILTER_NAME.FILTER_SLOT_NAME_3=B" 2>/dev/null || true
indi_setprop "Filter Simulator.FILTER_NAME.FILTER_SLOT_NAME_4=R" 2>/dev/null || true
indi_setprop "Filter Simulator.FILTER_NAME.FILTER_SLOT_NAME_5=I" 2>/dev/null || true
sleep 1

# Start at Luminance (wrong filter)
indi_setprop "Filter Simulator.FILTER_SLOT.FILTER_SLOT_VALUE=1" 2>/dev/null || true

# ── 6. Configure Focuser to nominal position ──────────────────────────
# Nominal is 30000. Agent must defocus to 30500.
indi_setprop 'Focuser Simulator.ABS_FOCUS_POSITION.FOCUS_ABSOLUTE_POSITION=30000' 2>/dev/null || true

# ── 7. Unpark telescope and slew to WRONG position ────────────────────
unpark_telescope
sleep 1
# Point at Sirius (RA ~6.75h, Dec ~-16.7°) - completely wrong target area
slew_to_coordinates 6.7525 -16.7161
wait_for_slew_complete 20
echo "Telescope at Sirius (wrong position). Agent must slew to HD 189733."

# ── 8. Configure CCD upload to a neutral location ──────────────────────
set_ccd_upload_dir "/home/ga/Images/captures"
indi_setprop "CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On" 2>/dev/null || true

# ── 9. Create the transit prediction document ──────────────────────────
cat > /home/ga/Documents/transit_prediction.txt << 'EOF'
============================================================
  EXOPLANET TRANSIT PREDICTION — HD 189733 b
  Czech Astronomical Society / Exoplanet Transit Database
============================================================

TARGET STAR:    HD 189733 (HIP 98505)
  Spectral Type:  K2V
  V magnitude:    7.67
  RA (J2000):     20h 00m 43.71s
  Dec (J2000):    +22° 42' 39.1"

PLANET:         HD 189733 b
  Type:           Hot Jupiter
  Period:         2.21857312 ± 0.00000076 days
  Transit Depth:  0.0241 (2.41%)
  Duration:       1.827 hours (109.6 minutes)
  Ephemeris T0:   2454279.436714 BJD (Agol et al. 2010)

OBSERVATION REQUIREMENTS:
  Filter:             V-band (filter slot 2)
  Exposure Time:      60 seconds
  Number of Frames:   ≥15 (covering at least 15 minutes of cadence)
  Defocus:            500 steps above nominal focus position (~30000)
                      Set focuser to absolute position 30500
  Frame Type:         LIGHT
  Upload Directory:   /home/ga/Images/transits/hd189733b/

COMPARISON STAR:
  HD 189585 (in same CCD field of view)
  V magnitude:    ~8.5
  Notes:          Used for differential photometry

OBSERVATION LOG:
  Save to: /home/ga/Documents/transit_log.txt
  Format:  ETD-compatible (see below)

  Required header fields:
    OBJECT:       HD 189733 b
    RA:           20 00 43.71
    DEC:          +22 42 39.1
    FILTER:       V
    EXPOSURE:     60
    DEFOCUS:      500
    COMP_STAR:    HD 189585
    TELESCOPE:    Simulated 200mm f/3.75
    CCD:          Simulated CCD
    OBSERVER:     [your identifier]

  Required data section:
    List each frame with: frame number, filename, and status (OK/BAD)

  End with:
    TOTAL_FRAMES: [count]
    NOTES: [any observing notes]

SKY VIEW:
  Capture with: bash ~/capture_sky_view.sh ~/Images/transits/hd189733b/sky_view.png
============================================================
EOF

chown ga:ga /home/ga/Documents/transit_prediction.txt
echo "Transit prediction written to /home/ga/Documents/transit_prediction.txt"

# ── 10. Ensure KStars is running and maximized ─────────────────────────
ensure_kstars_running
sleep 3

for i in 1 2; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
done

maximize_kstars
focus_kstars
sleep 1

# ── 11. Record initial FITS count for anti-gaming ─────────────────────
INITIAL_FITS=$(find /home/ga/Images/transits 2>/dev/null -name "*.fits" | wc -l)
echo "$INITIAL_FITS" > /tmp/initial_fits_count.txt

# ── 12. Take initial screenshot ───────────────────────────────────────
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Prediction document at: ~/Documents/transit_prediction.txt"
echo "Target: HD 189733 (RA 20h 00m 43.7s, Dec +22° 42' 39\")"