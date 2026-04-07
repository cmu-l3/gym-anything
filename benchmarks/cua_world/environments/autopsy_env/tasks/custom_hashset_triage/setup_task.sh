#!/bin/bash
# Setup script for custom_hashset_triage task

echo "=== Setting up custom_hashset_triage task ==="

source /workspace/scripts/task_utils.sh

# ── Clean up stale artifacts ──────────────────────────────────────────────────
rm -f /tmp/custom_hashset_result.json /tmp/custom_hashset_gt.json \
      /tmp/custom_hashset_start_time /home/ga/evidence/intel_hashes.txt 2>/dev/null || true

for d in /home/ga/Cases/Target_Hunting_2024*/; do
    [ -d "$d" ] && rm -rf "$d" && echo "Removed old case: $d"
done

rm -rf /home/ga/Reports/Hit_Exports
mkdir -p /home/ga/Reports/Hit_Exports
chown -R ga:ga /home/ga/Reports/ 2>/dev/null || true

# ── Verify disk image ─────────────────────────────────────────────────────────
IMAGE="/home/ga/evidence/ntfs_undel.dd"
if [ ! -s "$IMAGE" ]; then
    echo "ERROR: Disk image not found at $IMAGE"
    exit 1
fi
echo "Disk image: $IMAGE ($(stat -c%s "$IMAGE") bytes)"

# ── Generate Intel Hashes & Ground Truth ──────────────────────────────────────
echo "Generating target hashes from disk image..."
python3 << 'PYEOF'
import subprocess, json, hashlib, random, re

IMAGE = "/home/ga/evidence/ntfs_undel.dd"

try:
    result = subprocess.run(["fls", "-r", IMAGE], capture_output=True, text=True, timeout=60)
    lines = result.stdout.splitlines()
except Exception as e:
    print(f"WARNING: fls failed: {e}")
    lines = []

files = []
for line in lines:
    stripped = re.sub(r'^[+\s]+', '', line)
    # Ignore deleted for targets to ensure they are fully intact
    if ' * ' in stripped:
        continue
    m = re.match(r'^([\w/-]+)\s+(\d+)(?:-\S+)?:\s+(.+)', stripped)
    if not m:
        continue
    type_field = m.group(1)
    inode = m.group(2)
    name = m.group(3).strip()
    if '\t' in name:
        name = name.split('\t')[0].strip()
    if type_field.endswith('d') or type_field.endswith('v'):
        continue
    if name in ('.', '..') or name.startswith('$') or ':' in name:
        continue
    files.append({"name": name, "inode": inode})

# Seed randomly and pick 4
random.seed()
sampled = random.sample(files, min(4, len(files)))

target_hashes = []
gt_matches = {}

for f in sampled:
    try:
        icat = subprocess.run(["icat", IMAGE, f["inode"]], capture_output=True, timeout=10)
        if icat.returncode == 0 and icat.stdout:
            if len(icat.stdout) > 0:
                md5 = hashlib.md5(icat.stdout).hexdigest()
                target_hashes.append(md5)
                gt_matches[md5] = f["name"]
    except Exception:
        pass

# Pad with fake hashes if we couldn't get 4
while len(target_hashes) < 4:
    fake_md5 = hashlib.md5(str(random.random()).encode()).hexdigest()
    target_hashes.append(fake_md5)

with open("/home/ga/evidence/intel_hashes.txt", "w") as out:
    for h in target_hashes:
        out.write(h + "\n")

gt = {"targets": target_hashes, "matches": gt_matches, "image_path": IMAGE}
with open("/tmp/custom_hashset_gt.json", "w") as out:
    json.dump(gt, out, indent=2)

print(f"Selected {len(gt_matches)} real files for target intelligence list.")
PYEOF

chown ga:ga /home/ga/evidence/intel_hashes.txt

# ── Record task start time ────────────────────────────────────────────────────
date +%s > /tmp/custom_hashset_start_time

# ── Kill Autopsy and relaunch ─────────────────────────────────────────────────
kill_autopsy

echo "Launching Autopsy..."
launch_autopsy
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
    DISPLAY=:1 xdotool mousemove 960 540 click 1 2>/dev/null || true
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 5
    WELCOME_ELAPSED=$((WELCOME_ELAPSED + 5))
done

sleep 3
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "welcome"; then
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
fi

take_screenshot /tmp/task_initial_state.png ga
echo "=== Setup complete ==="