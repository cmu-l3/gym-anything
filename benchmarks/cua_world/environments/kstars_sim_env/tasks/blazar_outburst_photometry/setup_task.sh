#!/bin/bash
set -e
echo "=== Setting up blazar_outburst_photometry task ==="

source /workspace/scripts/task_utils.sh

# ── 1. Record task start time ─────────────────────────────────────────
date +%s > /tmp/task_start_time.txt

# ── 2. Clean up previous artifacts ────────────────────────────────────
rm -rf /home/ga/Images/blazar
rm -f /home/ga/Documents/atel_alert.txt
rm -f /home/ga/Documents/optical_counterpart_report.txt
rm -f /tmp/task_result.json

# ── 3. Create directories ──────────────────────────────────────────────
mkdir -p /home/ga/Images/blazar/mrk421
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Images/blazar
chown -R ga:ga /home/ga/Documents

# ── 4. ERROR INJECTION: Seed stale files ──────────────────────────────
# These should NOT count toward the required frames
touch -t 202401010000 /home/ga/Images/blazar/mrk421/old_calib_001.fits 2>/dev/null || true
touch -t 202401010000 /home/ga/Images/blazar/mrk421/old_calib_002.fits 2>/dev/null || true
touch -t 202401010000 /home/ga/Images/blazar/mrk421/old_calib_003.fits 2>/dev/null || true
chown -R ga:ga /home/ga/Images/blazar/mrk421

# ── 5. Start INDI ──────────────────────────────────────────────────────
ensure_indi_running
sleep 2
connect_all_devices

# ── 6. Configure filter wheel for BVR ─────────────────────────────────
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_1=L" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_2=V" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_3=B" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_4=R" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_5=I" 2>/dev/null || true
sleep 1

# ── 7. Unpark and slew to WRONG position ──────────────────────────────
unpark_telescope
sleep 1
# Point at M87 (Virgo A) - another AGN, but wrong target
slew_to_coordinates 12.513 12.391
wait_for_slew_complete 20
echo "Telescope at M87 (wrong). Agent must find Markarian 421."

# ── 8. Reset CCD ──────────────────────────────────────────────────────
set_ccd_upload_dir "/home/ga/Images/captures"
indi_setprop "CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On" 2>/dev/null || true

# ── 9. Create the ATel alert document ─────────────────────────────────
cat > /home/ga/Documents/atel_alert.txt << 'EOF'
ASTRONOMER'S TELEGRAM (ATel)
=============================
ATel #15984: Huge TeV Gamma-Ray Flare from Blazar Markarian 421
Subjects: Active Galactic Nuclei, Blazars, Gamma-Ray, Optical, Target of Opportunity

We report a major outburst of the high-frequency peaked BL Lac object
Markarian 421 (Mrk 421) detected by the TeV monitoring network. To accurately
model the jet physics and Spectral Energy Distribution (SED), we request
immediate ground-based optical follow-up.

TARGET INFORMATION
------------------
Object: Markarian 421 (Mrk 421)
Right Ascension: 11h 04m 27s
Declination: +38d 12m 31s (J2000)

REQUIRED OBSERVATIONS
---------------------
Please obtain a multi-band photometric sequence in B, V, and R filters.
Upload all images to: /home/ga/Images/blazar/mrk421/

Sequence requirements:
1. B-band (Slot 3): 5 frames x 120 seconds
2. V-band (Slot 2): 5 frames x 60 seconds
3. R-band (Slot 4): 5 frames x 60 seconds
(Frame type: LIGHT)

PRESS RELEASE VISUAL
--------------------
For our public outreach press release, we need an X-ray analog "heat" image
of the region. Generate a 0.5-degree field-of-view sky image exactly as follows:
bash ~/capture_sky_view.sh /home/ga/Images/blazar/mrk421/mrk421_xray_analog.png 0.5 --palette heat

REPORTING
---------
Write a short optical counterpart report at:
/home/ga/Documents/optical_counterpart_report.txt

The report must explicitly mention the target ("Markarian 421" or "Mrk 421")
and confirm that the B, V, and R sequence has been executed.
EOF

chown ga:ga /home/ga/Documents/atel_alert.txt

# ── 10. Ensure KStars is running ───────────────────────────────────────
ensure_kstars_running
sleep 3

for i in 1 2; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
done

maximize_kstars
focus_kstars
sleep 1

# ── 11. Record initial state ───────────────────────────────────────────
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "ATel at ~/Documents/atel_alert.txt"
echo "Target: Markarian 421 (RA 11h 04m 27s, Dec +38d 12m 31s)"
echo "Telescope at M87 - agent must discover and slew to Markarian 421"