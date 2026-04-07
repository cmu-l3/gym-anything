#!/bin/bash
# Setup script for known_hash_identification task

echo "=== Setting up known_hash_identification task ==="

source /workspace/scripts/task_utils.sh

# ── Clean up stale artifacts ──────────────────────────────────────────────────
rm -f /tmp/known_hash_result.json /tmp/known_hash_gt.json \
      /tmp/known_hash_start_time.txt /home/ga/evidence/known_bad_hashset.txt 2>/dev/null || true

for d in /home/ga/Cases/Hash_Lookup_2024*/; do
    [ -d "$d" ] && rm -rf "$d" && echo "Removed old case: $d"
done

mkdir -p /home/ga/Reports
chown -R ga:ga /home/ga/Reports/ 2>/dev/null || true

# ── Verify disk image ─────────────────────────────────────────────────────────
IMAGE="/home/ga/evidence/ntfs_undel.dd"
if [ ! -s "$IMAGE" ]; then
    echo "ERROR: Disk image not found at $IMAGE"
    exit 1
fi
echo "Disk image: $IMAGE ($(stat -c%s "$IMAGE") bytes)"

# ── Pre-compute Ground Truth & Generate Hash Set ─────────────────────────────
echo "Generating dynamic hash set and ground truth from image content..."
python3 << 'PYEOF'
import subprocess, json, re, hashlib, random, string

IMAGE = "/home/ga/evidence/ntfs_undel.dd"

# Use fls to get all files
try:
    result = subprocess.run(
        ["fls", "-r", IMAGE],
        capture_output=True, text=True, timeout=60
    )
    lines = result.stdout.splitlines()
except Exception as e:
    print(f"WARNING: fls failed: {e}")
    lines = []

files = []
for line in lines:
    stripped = re.sub(r'^[+\s]+', '', line)
    is_deleted = ' * ' in stripped
    m = re.match(r'^([\w/-]+)\s+(?:\*\s+)?(\d+)(?:-\S+)?:\s+(.+)', stripped)
    if not m:
        continue
    type_field = m.group(1)
    inode = m.group(2)
    name = m.group(3).strip()
    if '\t' in name:
        name = name.split('\t')[0].strip()
    # Only regular files
    if type_field.endswith('d') or type_field.endswith('v'):
        continue
    if name in ('.', '..') or name.startswith('$') or ':' in name:
        continue
    files.append({"name": name, "inode": inode, "deleted": is_deleted})

# Randomly select a few files to be our "known bads"
random.seed() # Different every time to prevent hardcoded gaming
random.shuffle(files)

known_bads = []
for f in files:
    try:
        icat = subprocess.run(["icat", IMAGE, f["inode"]], capture_output=True, timeout=5)
        if icat.returncode == 0 and len(icat.stdout) > 0:
            md5 = hashlib.md5(icat.stdout).hexdigest()
            # Ensure uniqueness
            if md5 not in [x["md5"] for x in known_bads]:
                f["md5"] = md5
                f["size"] = len(icat.stdout)
                known_bads.append(f)
    except Exception:
        continue
    
    if len(known_bads) == 4:
        break

# Generate decoy hashes (hashes that do not match anything on the disk)
decoys = [
    ''.join(random.choices(string.hexdigits.lower(), k=32)),
    ''.join(random.choices(string.hexdigits.lower(), k=32)),
    ''.join(random.choices(string.hexdigits.lower(), k=32))
]

all_hashes = [x["md5"] for x in known_bads] + decoys
random.shuffle(all_hashes)

# Write the hash set to disk
hashset_path = "/home/ga/evidence/known_bad_hashset.txt"
with open(hashset_path, "w") as f:
    for h in all_hashes:
        f.write(h + "\n")

# Save ground truth (hidden from agent)
gt = {
    "total_hashes": len(all_hashes),
    "matching_md5s": [x["md5"] for x in known_bads],
    "decoy_md5s": decoys,
    "matching_files": known_bads,
    "hashset_path": hashset_path
}
with open("/tmp/known_hash_gt.json", "w") as f:
    json.dump(gt, f, indent=2)

print(f"Generated hash set with {len(all_hashes)} hashes ({len(known_bads)} real, {len(decoys)} decoys)")
for kb in known_bads:
    status = "DEL" if kb["deleted"] else "ALLOC"
    print(f"  True Hit: {kb['md5']} -> {kb['name']} [{status}]")
PYEOF

chown ga:ga /home/ga/evidence/known_bad_hashset.txt 2>/dev/null || true

if [ ! -f /tmp/known_hash_gt.json ]; then
    echo "FATAL: Failed to generate ground truth"
    exit 1
fi

# ── Record task start time ────────────────────────────────────────────────────
date +%s > /tmp/known_hash_start_time.txt

# ── Launch Autopsy and wait for UI ────────────────────────────────────────────
kill_autopsy
echo "Launching Autopsy..."
launch_autopsy

wait_for_autopsy_window 300

WELCOME_TIMEOUT=360
WELCOME_ELAPSED=0
WELCOME_FOUND=false

while [ $WELCOME_ELAPSED -lt $WELCOME_TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "welcome"; then
        echo "Welcome screen detected after ${WELCOME_ELAPSED}s"
        WELCOME_FOUND=true
        break
    fi
    DISPLAY=:1 xdotool mousemove 960 540 click 1 2>/dev/null || true
    sleep 5
    WELCOME_ELAPSED=$((WELCOME_ELAPSED + 5))
done

if [ "$WELCOME_FOUND" = false ]; then
    echo "WARNING: Autopsy Welcome screen did not appear in time."
fi

# Try to maximize and focus
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Autopsy" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

sleep 2
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="