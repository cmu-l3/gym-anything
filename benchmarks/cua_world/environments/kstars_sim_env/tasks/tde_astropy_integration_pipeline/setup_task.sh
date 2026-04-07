#!/bin/bash
set -e
echo "=== Setting up tde_astropy_integration_pipeline task ==="

source /workspace/scripts/task_utils.sh

# 1. Clean up previous artifacts
rm -rf /home/ga/Images/tde_monitoring
rm -f /home/ga/Documents/tde_followup_brief.txt
rm -f /home/ga/Documents/integration_summary.json
rm -f /tmp/task_result.json
rm -f /tmp/ground_truth_summary.json

mkdir -p /home/ga/Images/tde_monitoring/asassn14li
mkdir -p /home/ga/Documents

# 2. Seed "crashed run" FITS files using Astropy (simulate a prior partial session)
# These files will have mtime strictly BEFORE the task_start_time.
cat > /tmp/generate_fake_fits.py << 'EOF'
import os
import random
import numpy as np
from astropy.io import fits

target_dir = '/home/ga/Images/tde_monitoring/asassn14li'
filters = ['L', 'V', 'B', 'R', 'I']

num_files = random.randint(4, 8)
for i in range(num_files):
    filt = random.choice(filters)
    exp = float(random.choice([15, 30, 45, 60, 120, 300]))
    
    # Create a tiny 10x10 dummy FITS
    data = np.zeros((10, 10), dtype=np.uint16)
    hdu = fits.PrimaryHDU(data)
    hdu.header['EXPTIME'] = exp
    hdu.header['FILTER'] = filt
    hdu.header['OBJECT'] = 'ASASSN-14li'
    
    filepath = os.path.join(target_dir, f'crashed_run_frame_{i:03d}.fits')
    hdu.writeto(filepath, overwrite=True)
EOF

python3 /tmp/generate_fake_fits.py
chown -R ga:ga /home/ga/Images/tde_monitoring

# Wait to ensure timestamps of generated files are clearly older than task start
sleep 2
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 3. Start INDI and simulators
ensure_indi_running
sleep 2
connect_all_devices

# 4. Configure filter wheel with names (so they write correct strings to FITS headers)
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_1=L" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_2=V" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_3=B" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_4=R" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_5=I" 2>/dev/null || true
sleep 1

# 5. Unpark and slew to WRONG position (M82)
unpark_telescope
sleep 1
slew_to_coordinates 9.92 69.67
wait_for_slew_complete 20
echo "Telescope at M82 (wrong position). Agent must slew to ASASSN-14li."

# 6. Set generic CCD upload dir (agent must configure the specific one)
set_ccd_upload_dir "/home/ga/Images/captures"
indi_setprop "CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On" 2>/dev/null || true

# 7. Write the brief
cat > /home/ga/Documents/tde_followup_brief.txt << 'EOF'
TDE FOLLOWUP OPERATIONS BRIEF: ASASSN-14li
==========================================
Status: URGENT - Automated schedule crashed overnight.

TARGET INFO:
- Object: ASASSN-14li (Tidal Disruption Event)
- RA: 12h 48m 15.2s
- Dec: +17d 46m 26.4s (J2000)

INCOMPLETE ACQUISITION:
The telescope stopped responding midway through last night's sequence. Some FITS files 
survived and are currently in the target directory:
/home/ga/Images/tde_monitoring/asassn14li/

YOUR TASKS:
1. Slew the telescope to the ASASSN-14li coordinates.
2. Set the CCD upload directory to: /home/ga/Images/tde_monitoring/asassn14li/
3. Acquire the missing B-band frames:
   - Filter: B (Slot 3)
   - Exposure: 120 seconds
   - Count: 5 frames (LIGHT)
4. Acquire the missing V-band frames:
   - Filter: V (Slot 2)
   - Exposure: 60 seconds
   - Count: 5 frames (LIGHT)
5. Capture a Sky View context image of the field using the system script:
   bash ~/capture_sky_view.sh /home/ga/Images/tde_monitoring/asassn14li/sky_view.png 0.5
6. WRITE A PYTHON SCRIPT using the `astropy.io.fits` library to iterate through ALL 
   `.fits` files in the upload directory (both the pre-existing ones and the ones you 
   just acquired).
7. The Python script must sum the total exposure time (`EXPTIME`) grouped by the 
   filter name (`FILTER` header string).
8. Save the output to: /home/ga/Documents/integration_summary.json
   The JSON file must map the exact filter string to the total exposure seconds.
   Example expected structure: {"B": 720.0, "V": 450.0, "R": 120.0}

NOTE: The true FITS headers hold the exact metadata you need to aggregate. Do not 
hardcode sums; let your Python script compute them dynamically.
EOF

chown ga:ga /home/ga/Documents/tde_followup_brief.txt

# 8. Start and configure KStars
ensure_kstars_running
sleep 3
for i in 1 2; do DISPLAY=:1 xdotool key Escape 2>/dev/null || true; sleep 1; done
maximize_kstars
focus_kstars
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="