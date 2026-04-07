#!/bin/bash
set -e
echo "=== Setting up automated_galaxy_cluster_atlas_generation task ==="

source /workspace/scripts/task_utils.sh

# ── 1. Record task start time ─────────────────────────────────────────
date +%s > /tmp/task_start_time.txt

# ── 2. Clean up previous artifacts ────────────────────────────────────
rm -rf /home/ga/Images/cluster_atlas
rm -f /home/ga/build_atlas.sh
rm -f /home/ga/build_atlas.py
rm -f /home/ga/Documents/cluster_catalog.csv
rm -f /tmp/task_result.json

# ── 3. Create required directories ────────────────────────────────────
mkdir -p /home/ga/Images
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Images
chown -R ga:ga /home/ga/Documents

# ── 4. Start INDI and connect devices ─────────────────────────────────
ensure_indi_running
sleep 2
connect_all_devices

# ── 5. Unpark telescope and slew to an unrelated starting position ────
unpark_telescope
sleep 1
# Point at M42 (Orion Nebula) to ensure a fresh starting position
slew_to_coordinates 5.5881 -5.3911
wait_for_slew_complete 20

# ── 6. Create the target catalog CSV ──────────────────────────────────
cat > /home/ga/Documents/cluster_catalog.csv << 'EOF'
ID,RA_J2000,Dec_J2000,Redshift
Abell_1689,13:11:29.5,-01:20:28,0.183
Abell_2744,00:14:19.5,-30:23:19,0.308
MACS_J0717,07:17:31.6,+37:45:18,0.545
Bullet_Cluster,06:58:31.1,-55:56:49,0.296
El_Gordo,01:02:53.0,-49:15:19,0.870
Coma_Cluster,12:59:48.7,+27:58:50,0.023
Perseus_Cluster,03:19:48.1,+41:30:42,0.019
RXJ1347_1145,13:47:30.6,-11:45:09,0.451
Abell_370,02:39:52.9,-01:34:36,0.375
MACS_J1149,11:49:35.8,+22:23:54,0.544
EOF
chown ga:ga /home/ga/Documents/cluster_catalog.csv

# ── 7. Ensure KStars is running and maximized ─────────────────────────
ensure_kstars_running
sleep 3
for i in 1 2; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
done
maximize_kstars
focus_kstars
sleep 1

# ── 8. Take initial screenshot ────────────────────────────────────────
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Target catalog located at: ~/Documents/cluster_catalog.csv"
echo "Telescope ready. The agent must write the automation script."