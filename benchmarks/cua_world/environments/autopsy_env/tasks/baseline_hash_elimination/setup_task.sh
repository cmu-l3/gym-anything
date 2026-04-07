#!/bin/bash
echo "=== Setting up baseline_hash_elimination task ==="

source /workspace/scripts/task_utils.sh

# ── Clean up stale artifacts ──────────────────────────────────────────────────
rm -f /tmp/baseline_task_result.json /tmp/baseline_gt.json \
      /tmp/baseline_start_time 2>/dev/null || true

for d in /home/ga/Cases/Exfiltration_Analysis_2026*/; do
    [ -d "$d" ] && rm -rf "$d" && echo "Removed old case: $d"
done

mkdir -p /home/ga/Reports
chown -R ga:ga /home/ga/Reports/ 2>/dev/null || true
mkdir -p /home/ga/evidence
chown -R ga:ga /home/ga/evidence/ 2>/dev/null || true

# ── Generate Authentic Real Data Images ───────────────────────────────────────
echo "Generating genuine file corpus for baseline and suspect images..."

python3 << 'PYEOF'
import os, shutil, hashlib, json

source_dir = '/usr/lib/python3'
source_files = []

# Collect real python files to serve as "corporate documents" and "user scripts"
for root, dirs, files in os.walk(source_dir):
    for f in files:
        if f.endswith('.py'):
            p = os.path.join(root, f)
            if 1000 < os.path.getsize(p) < 50000:
                source_files.append(p)
        if len(source_files) >= 65:
            break
    if len(source_files) >= 65:
        break

os.makedirs('/tmp/baseline_files', exist_ok=True)
os.makedirs('/tmp/suspect_files', exist_ok=True)

gt = {"baseline": {}, "anomalous": {}}

for i, src in enumerate(source_files):
    if i < 50:
        # Baseline files (both in baseline and suspect)
        dst_name = f"corp_script_{i:03d}.py"
        dst_base = os.path.join('/tmp/baseline_files', dst_name)
        dst_susp = os.path.join('/tmp/suspect_files', dst_name)
        shutil.copy(src, dst_base)
        shutil.copy(src, dst_susp)
        
        md5 = hashlib.md5(open(dst_base, 'rb').read()).hexdigest()
        gt["baseline"][dst_name] = md5
    else:
        # Anomalous files (only in suspect)
        dst_name = f"exfiltrated_data_{i:03d}.py"
        dst_susp = os.path.join('/tmp/suspect_files', dst_name)
        shutil.copy(src, dst_susp)
        
        md5 = hashlib.md5(open(dst_susp, 'rb').read()).hexdigest()
        gt["anomalous"][dst_name] = md5

with open("/tmp/baseline_gt.json", "w") as f:
    json.dump(gt, f, indent=2)
PYEOF

echo "Creating FAT32 Disk Images..."
# 35MB images to satisfy mkfs.vfat minimum requirements safely
dd if=/dev/zero of=/home/ga/evidence/corporate_baseline.dd bs=1M count=35 2>/dev/null
mkfs.vfat -F 32 -n "BASELINE" /home/ga/evidence/corporate_baseline.dd >/dev/null
mcopy -i /home/ga/evidence/corporate_baseline.dd /tmp/baseline_files/* ::/

dd if=/dev/zero of=/home/ga/evidence/suspect_seized.dd bs=1M count=35 2>/dev/null
mkfs.vfat -F 32 -n "SUSPECT" /home/ga/evidence/suspect_seized.dd >/dev/null
mcopy -i /home/ga/evidence/suspect_seized.dd /tmp/suspect_files/* ::/

chown ga:ga /home/ga/evidence/corporate_baseline.dd
chown ga:ga /home/ga/evidence/suspect_seized.dd

# Cleanup temps
rm -rf /tmp/baseline_files /tmp/suspect_files

# ── Record task start time ────────────────────────────────────────────────────
date +%s > /tmp/baseline_start_time

# ── Launch Autopsy ────────────────────────────────────────────────────────────
kill_autopsy
echo "Launching Autopsy..."
launch_autopsy

echo "Waiting for Autopsy process to start..."
wait_for_autopsy_window 300

WELCOME_TIMEOUT=420
WELCOME_ELAPSED=0
WELCOME_FOUND=false

while [ $WELCOME_ELAPSED -lt $WELCOME_TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "welcome"; then
        echo "Welcome screen detected after ${WELCOME_ELAPSED}s"
        WELCOME_FOUND=true
        break
    fi
    # Keep screen awake and dismiss potential splash screen freezes
    DISPLAY=:1 xdotool mousemove 960 540 click 1 2>/dev/null || true
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 5
    WELCOME_ELAPSED=$((WELCOME_ELAPSED + 5))
done

if [ "$WELCOME_FOUND" = false ]; then
    echo "ERROR: Autopsy Welcome screen did NOT appear within ${WELCOME_TIMEOUT}s"
    # Last ditch effort
    kill_autopsy
    sleep 2
    launch_autopsy
fi

sleep 3
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

take_screenshot /tmp/task_initial.png ga

echo "=== Task Setup Complete ==="