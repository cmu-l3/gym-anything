#!/bin/bash
# Setup script for legal_constraint_media_extraction task

echo "=== Setting up legal_constraint_media_extraction task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ── Clean up stale artifacts ──────────────────────────────────────────────────
rm -f /tmp/legal_constraint_result.json /tmp/legal_constraint_gt.json 2>/dev/null || true

for d in /home/ga/Cases/Warrant_Compliance_2024*/; do
    [ -d "$d" ] && rm -rf "$d" && echo "Removed old case: $d"
done

mkdir -p /home/ga/Reports
chown -R ga:ga /home/ga/Reports/ 2>/dev/null || true

# ── Verify disk image ─────────────────────────────────────────────────────────
IMAGE="/home/ga/evidence/jpeg_search.dd"
if [ ! -s "$IMAGE" ]; then
    echo "ERROR: Disk image not found at $IMAGE"
    exit 1
fi
echo "Disk image: $IMAGE ($(stat -c%s "$IMAGE") bytes)"

# ── Pre-compute TSK ground truth (Allocated vs Deleted Hashes) ────────────────
echo "Pre-computing ground truth from TSK (Hashing Allocated & Deleted files)..."
python3 << 'PYEOF'
import subprocess, json, re, hashlib, sys

IMAGE = "/home/ga/evidence/jpeg_search.dd"

try:
    result = subprocess.run(["fls", "-r", IMAGE], capture_output=True, text=True, timeout=60)
    lines = result.stdout.splitlines()
except Exception as e:
    print(f"WARNING: fls failed: {e}")
    lines = []

allocated_hashes = set()
deleted_hashes = set()
jpeg_exts = {".jpg", ".jpeg", ".jfif"}

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
        
    if type_field.endswith('d') or type_field.endswith('v'):
        continue
    if name in ('.', '..') or name.startswith('$') or ':' in name:
        continue
        
    ext = ""
    dot_pos = name.rfind('.')
    if dot_pos >= 0:
        ext = name[dot_pos:].lower()
        
    if ext in jpeg_exts:
        # Extract and hash the file content using icat
        icat = subprocess.run(["icat", IMAGE, inode], capture_output=True, timeout=10)
        if icat.returncode == 0 and icat.stdout:
            h = hashlib.md5(icat.stdout).hexdigest()
            if is_deleted:
                deleted_hashes.add(h)
            else:
                allocated_hashes.add(h)

# Some files might identical in both allocated and deleted space.
# We only penalize if they extract a file that is ONLY found in deleted space.
pure_deleted = deleted_hashes - allocated_hashes

gt = {
    "allocated_hashes": list(allocated_hashes),
    "pure_deleted_hashes": list(pure_deleted),
    "allocated_count": len(allocated_hashes),
    "pure_deleted_count": len(pure_deleted)
}

with open("/tmp/legal_constraint_gt.json", "w") as f:
    json.dump(gt, f, indent=2)

print(f"Ground truth: {len(allocated_hashes)} allocated unique JPEGs, {len(pure_deleted)} strictly deleted unique JPEGs.")
PYEOF

# ── Ensure Autopsy is running ─────────────────────────────────────────────────
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
    DISPLAY=:1 xdotool mousemove 960 540 click 1 2>/dev/null || true
    sleep 5
    WELCOME_ELAPSED=$((WELCOME_ELAPSED + 5))
done

if [ "$WELCOME_FOUND" = false ]; then
    echo "WARNING: Autopsy Welcome screen detection timed out. Proceeding anyway..."
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="