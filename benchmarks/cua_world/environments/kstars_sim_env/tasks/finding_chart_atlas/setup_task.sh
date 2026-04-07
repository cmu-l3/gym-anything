#!/bin/bash
set -e
echo "=== Setting up finding_chart_atlas task ==="

source /workspace/scripts/task_utils.sh

# ── 1. Record task start time ─────────────────────────────────────────
date +%s > /tmp/task_start_time.txt

# ── 2. Clean up previous artifacts ────────────────────────────────────
rm -rf /home/ga/Images/finding_charts
rm -f /home/ga/Documents/observing_plan.txt
rm -f /tmp/task_result.json

# ── 3. Create directories ──────────────────────────────────────────────
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Documents

# ── 4. Start INDI ──────────────────────────────────────────────────────
ensure_indi_running
sleep 2
connect_all_devices

# ── 5. Unpark and slew to NCP (wrong position) ────────────────────────
unpark_telescope
sleep 1
# Point at North Celestial Pole, far from targets
slew_to_coordinates 2.5 89.0
wait_for_slew_complete 20
echo "Telescope at NCP. Agent must find targets."

# ── 6. Create the observing plan document ───────────────────────────
cat > /home/ga/Documents/observing_plan.txt << 'EOF'
REMOTE OBSERVING RUN - TARGET FINDING CHARTS
==============================================
Observer: Dr. V. Astronomer
Instrument: Facility CCD + Telescope
Output Directory: /home/ga/Images/finding_charts/

Please prepare finding charts for the following targets. For each target:
1. Slew the telescope to the specified coordinates.
2. Use the `capture_sky_view.sh` script to capture the field.
   NOTE: The script takes FOV in *degrees*, so you must convert the arcminute FOV requested below into degrees.
   Usage: bash ~/capture_sky_view.sh [output_path] [fov_degrees] --palette [palette_name]

TARGET 1: Abell 2218
- Type: Galaxy Cluster
- Coordinates (J2000): RA 16h 35m 54s, Dec +66d 12m 00s
- Required FOV: 10 arcminutes
- Palette: enhanced
- Filename: abell2218_fc.png

TARGET 2: M1 (Crab Nebula)
- Type: Supernova Remnant
- Coordinates (J2000): RA 05h 34m 32s, Dec +22d 00m 52s
- Required FOV: 15 arcminutes
- Palette: hubble
- Filename: m1_crab_fc.png

TARGET 3: Sgr A* Region
- Type: Galactic Center
- Coordinates (J2000): RA 17h 45m 40s, Dec -29d 00m 28s
- Required FOV: 30 arcminutes
- Palette: heat
- Filename: sgra_gc_fc.png

TARGET 4: 3C 273
- Type: Quasar
- Coordinates (J2000): RA 12h 29m 07s, Dec +02d 03m 09s
- Required FOV: 5 arcminutes
- Palette: cool
- Filename: 3c273_fc.png

ATLAS INDEX REQUIRED
--------------------
After capturing all charts, create an index file at:
/home/ga/Images/finding_charts/atlas_index.txt

The file must list all 4 targets with their names, coordinates, FOV, and filename.
EOF

chown ga:ga /home/ga/Documents/observing_plan.txt

# ── 7. Ensure KStars is running ────────────────────────────────────────
ensure_kstars_running
sleep 3

for i in 1 2; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
done

maximize_kstars
focus_kstars
sleep 1

take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="