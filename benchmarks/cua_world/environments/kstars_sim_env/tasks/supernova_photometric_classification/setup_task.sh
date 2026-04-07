#!/bin/bash
set -e
echo "=== Setting up supernova_photometric_classification task ==="

source /workspace/scripts/task_utils.sh

# ── 1. Clean previous artifacts ──────────────────────────────────────
rm -rf /home/ga/Images/sn_followup
rm -f /home/ga/reduce_photometry.py
rm -f /home/ga/classification.json
rm -f /home/ga/Documents/ztf_alert_AT2026xy.txt
rm -f /home/ga/Documents/atel_draft.txt
rm -f /tmp/task_result.json

# ── 2. Record task start time (after cleanup) ────────────────────────
sleep 1
date +%s > /tmp/task_start_time.txt

# ── 3. Create directory structure ────────────────────────────────────
mkdir -p /home/ga/Images/sn_followup/reference
mkdir -p /home/ga/Images/sn_followup/candidate/B
mkdir -p /home/ga/Images/sn_followup/candidate/V
mkdir -p /home/ga/Images/sn_followup/candidate/R
mkdir -p /home/ga/Images/sn_followup/standard/B
mkdir -p /home/ga/Images/sn_followup/standard/V
mkdir -p /home/ga/Images/sn_followup/standard/R
mkdir -p /home/ga/Images/sn_followup/charts
mkdir -p /home/ga/Documents

# ── 4. Inject stale anti-gaming files ────────────────────────────────
# Pre-existing FITS with old mtime; agent must not count these
touch -t 202401150000 /home/ga/Images/sn_followup/reference/old_reference_001.fits 2>/dev/null || true
touch -t 202401150000 /home/ga/Images/sn_followup/reference/old_reference_002.fits 2>/dev/null || true
touch -t 202401150000 /home/ga/Images/sn_followup/candidate/V/stale_v_001.fits 2>/dev/null || true

chown -R ga:ga /home/ga/Images/sn_followup
chown -R ga:ga /home/ga/Documents

# ── 5. Start INDI and connect devices ────────────────────────────────
ensure_indi_running
sleep 2
connect_all_devices

# ── 6. Configure filter wheel ────────────────────────────────────────
# Set names on both Filter Simulator and CCD Simulator devices
for DEV in "Filter Simulator" "CCD Simulator"; do
    indi_setprop "${DEV}.FILTER_NAME.FILTER_SLOT_NAME_1=Luminance" 2>/dev/null || true
    indi_setprop "${DEV}.FILTER_NAME.FILTER_SLOT_NAME_2=V" 2>/dev/null || true
    indi_setprop "${DEV}.FILTER_NAME.FILTER_SLOT_NAME_3=B" 2>/dev/null || true
    indi_setprop "${DEV}.FILTER_NAME.FILTER_SLOT_NAME_4=R" 2>/dev/null || true
    indi_setprop "${DEV}.FILTER_NAME.FILTER_SLOT_NAME_5=Ha" 2>/dev/null || true
    indi_setprop "${DEV}.FILTER_NAME.FILTER_SLOT_NAME_6=OIII" 2>/dev/null || true
done
sleep 1

# ── 7. Unpark telescope and slew to wrong position ───────────────────
# Start at Polaris — agent must slew to the Virgo targets
unpark_telescope
sleep 1
slew_to_coordinates 2.5 89.26
wait_for_slew_complete 20

# ── 8. Reset CCD to default upload directory ─────────────────────────
set_ccd_upload_dir "/home/ga/Images/captures"
indi_setprop "CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On" 2>/dev/null || true

# ── 9. Write the ZTF Alert / Follow-Up Protocol Document ────────────
cat > /home/ga/Documents/ztf_alert_AT2026xy.txt << 'ALERTDOC'
================================================================
ZTF TRANSIENT ALERT — CLASSIFICATION PRIORITY: IMMEDIATE
================================================================
Designation:   AT2026xy
Alert Time:    2026-03-19T22:15:00 UTC
Discovery Mag: 17.2 (ZTF r-band)

CANDIDATE POSITION (J2000):
  RA:  12h 33m 52.0s
  Dec: +07d 41' 48.0"

HOST GALAXY:
  Name: NGC 4526 (Virgo Cluster lenticular)
  RA:   12h 34m 03.0s
  Dec:  +07d 41' 57.0"
  Offset from nucleus: ~164" W, ~9" S
  Redshift: z = 0.00206 (d ~ 16.9 Mpc)

================================================================
FOLLOW-UP PROTOCOL
================================================================

You must complete all five phases below. All coordinates, filter
slots, exposure times, and output paths are specified exactly.

────────────────────────────────────────────────────────────────
PHASE 1 — HOST GALAXY REFERENCE IMAGING
────────────────────────────────────────────────────────────────
Target:    NGC 4526 (RA 12h 34m 03.0s, Dec +07d 41' 57.0")
Filter:    Luminance (Slot 1)
Exposure:  60 seconds
Count:     3 frames minimum
Save to:   /home/ga/Images/sn_followup/reference/

After capturing, generate a 0.5-degree finding chart:
  bash ~/capture_sky_view.sh \
    /home/ga/Images/sn_followup/charts/finding_chart.png \
    0.5 --palette cool

────────────────────────────────────────────────────────────────
PHASE 2 — CANDIDATE MULTI-BAND PHOTOMETRY
────────────────────────────────────────────────────────────────
Target:    AT2026xy (RA 12h 33m 52.0s, Dec +07d 41' 48.0")
Filters:   B (Slot 3), V (Slot 2), R (Slot 4)
Exposure:  30 seconds per frame
Count:     5 frames per filter (minimum)
Save to:
  B-band:  /home/ga/Images/sn_followup/candidate/B/
  V-band:  /home/ga/Images/sn_followup/candidate/V/
  R-band:  /home/ga/Images/sn_followup/candidate/R/

────────────────────────────────────────────────────────────────
PHASE 3 — STANDARD STAR CALIBRATION
────────────────────────────────────────────────────────────────
Target:    Landolt standard field SA 104
           RA 12h 42m 00.0s, Dec -00d 32' 00.0"
Filters:   B (Slot 3), V (Slot 2), R (Slot 4)
Exposure:  15 seconds per frame
Count:     3 frames per filter (minimum)
Save to:
  B-band:  /home/ga/Images/sn_followup/standard/B/
  V-band:  /home/ga/Images/sn_followup/standard/V/
  R-band:  /home/ga/Images/sn_followup/standard/R/

Known standard magnitudes for SA 104:
  B = 11.24 mag
  V = 10.51 mag
  R = 10.12 mag

────────────────────────────────────────────────────────────────
PHASE 4 — DATA REDUCTION
────────────────────────────────────────────────────────────────
Write a Python script at /home/ga/reduce_photometry.py that:

  1. Uses astropy.io.fits to open every FITS file in the
     candidate/ and standard/ subdirectories
  2. For each frame, computes the median pixel value (ADU)
  3. Computes instrumental magnitude per frame:
       m_inst = -2.5 * log10(median_ADU)
  4. Averages the instrumental magnitudes per filter for both
     the candidate and the standard field
  5. Computes zero-point per filter:
       ZP = m_known_std - m_inst_std
     where m_known_std is the SA 104 magnitude listed above
  6. Applies zero-point to the candidate:
       m_calibrated = m_inst_candidate + ZP
  7. Computes color indices:
       B_minus_V = m_cal_B - m_cal_V
       V_minus_R = m_cal_V - m_cal_R
  8. Classifies supernova type:
       B-V < 0.2           -> Type Ia
       0.2 <= B-V <= 0.8   -> Type II-P
       B-V > 0.8           -> Type Ib/c
  9. Writes output to /home/ga/classification.json with keys:
       candidate_B_mag     (float)
       candidate_V_mag     (float)
       candidate_R_mag     (float)
       B_minus_V           (float)
       V_minus_R           (float)
       sn_type_estimate    (string: "Ia", "II-P", or "Ib/c")

Run the script after writing it to produce classification.json.

────────────────────────────────────────────────────────────────
PHASE 5 — ASTRONOMER'S TELEGRAM DRAFT
────────────────────────────────────────────────────────────────
Write /home/ga/Documents/atel_draft.txt containing:

  - Subject line including "AT2026xy"
  - Candidate J2000 coordinates (RA and Dec)
  - Host galaxy identification (NGC 4526)
  - Calibrated B, V, R magnitudes from classification.json
  - Color indices (B-V) and (V-R)
  - Preliminary supernova type classification with reasoning

================================================================
ALERTDOC
chown ga:ga /home/ga/Documents/ztf_alert_AT2026xy.txt

# ── 10. Ensure KStars is running and focused ─────────────────────────
ensure_kstars_running
sleep 3
for i in 1 2; do DISPLAY=:1 xdotool key Escape 2>/dev/null || true; sleep 1; done
maximize_kstars
focus_kstars
sleep 1

# ── 11. Record initial state ─────────────────────────────────────────
take_screenshot /tmp/task_initial.png

echo "=== supernova_photometric_classification setup complete ==="
