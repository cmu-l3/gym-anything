#!/bin/bash
# Setup script for jpeg_evidence_cataloging task

echo "=== Setting up jpeg_evidence_cataloging task ==="

source /workspace/scripts/task_utils.sh

# ── Clean up stale artifacts ──────────────────────────────────────────────────
rm -f /tmp/jpeg_evidence_result.json /tmp/jpeg_evidence_gt.json \
      /tmp/jpeg_evidence_start_time 2>/dev/null || true

for d in /home/ga/Cases/JPEG_Catalog_2024*/; do
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

# ── Pre-compute TSK ground truth (JPEG files) ─────────────────────────────────
echo "Pre-computing ground truth from TSK (JPEG files)..."
python3 << 'PYEOF'
import subprocess, json, re, sys

IMAGE = "/home/ga/evidence/jpeg_search.dd"

# Get all files including deleted
try:
    result = subprocess.run(
        ["fls", "-r", IMAGE],
        capture_output=True, text=True, timeout=60
    )
    lines = result.stdout.splitlines()
except Exception as e:
    print(f"WARNING: fls failed: {e}")
    lines = []

jpeg_files = []
jpeg_exts = {".jpg", ".jpeg", ".jfif"}

for line in lines:
    # fls format: "TYPE * INODE: NAME" for deleted, "TYPE INODE: NAME" for allocated
    # TYPE can be r/r (alloc), -/r (unalloc dir-entry), etc.
    # Nested entries have leading "+ " or "++ "
    # Strip depth prefix
    stripped = re.sub(r'^[+\s]+', '', line)
    is_deleted = ' * ' in stripped
    # Parse: TYPE [*] INODE[-seq[-attr]]: NAME
    m = re.match(r'^([\w/-]+)\s+(?:\*\s+)?(\d+)(?:-\S+)?:\s+(.+)', stripped)
    if not m:
        continue
    type_field = m.group(1)
    inode = m.group(2)
    name = m.group(3).strip()
    if '\t' in name:
        name = name.split('\t')[0].strip()
    # Only regular files (type ends in r, not d)
    if type_field.endswith('d') or type_field.endswith('v'):
        continue
    if name in ('.', '..') or name.startswith('$') or ':' in name:
        continue
    ext = ""
    dot_pos = name.rfind('.')
    if dot_pos >= 0:
        ext = name[dot_pos:].lower()
    if ext in jpeg_exts:
        jpeg_files.append({
            "name": name,
            "inode": inode,
            "deleted": is_deleted,
            "allocated": not is_deleted
        })

gt = {
    "jpeg_files": jpeg_files,
    "total_jpegs": len(jpeg_files),
    "allocated_count": sum(1 for f in jpeg_files if f["allocated"]),
    "deleted_count": sum(1 for f in jpeg_files if not f["allocated"]),
    "jpeg_names": [f["name"] for f in jpeg_files],
    "image_path": IMAGE
}
with open("/tmp/jpeg_evidence_gt.json", "w") as f:
    json.dump(gt, f, indent=2)

print(f"Ground truth: {gt['total_jpegs']} JPEG files found "
      f"({gt['allocated_count']} allocated, {gt['deleted_count']} deleted/carved)")
for jf in jpeg_files:
    status = "DELETED" if jf["deleted"] else "ALLOC"
    print(f"  [{status}] inode={jf['inode']}: {jf['name']}")
PYEOF

if [ ! -f /tmp/jpeg_evidence_gt.json ]; then
    echo "WARNING: GT computation failed"
    echo '{"jpeg_files":[],"total_jpegs":0,"allocated_count":0,"deleted_count":0,"jpeg_names":[]}' \
        > /tmp/jpeg_evidence_gt.json
fi

# ── Record task start time ────────────────────────────────────────────────────
date +%s > /tmp/jpeg_evidence_start_time

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
    if [ $((WELCOME_ELAPSED % 60)) -eq 0 ]; then
        if ! pgrep -f "/opt/autopsy" >/dev/null 2>&1; then
            echo "Autopsy died, relaunching..."
            launch_autopsy
        fi
    fi
done

if [ "$WELCOME_FOUND" = false ]; then
    kill_autopsy; sleep 2; launch_autopsy
    FINAL_ELAPSED=0
    while [ $FINAL_ELAPSED -lt 120 ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "welcome"; then
            WELCOME_FOUND=true; break
        fi
        DISPLAY=:1 xdotool mousemove 960 540 click 1 2>/dev/null || true
        sleep 5; FINAL_ELAPSED=$((FINAL_ELAPSED + 5))
    done
    [ "$WELCOME_FOUND" = false ] && echo "FATAL: Welcome screen never appeared." && exit 1
fi

sleep 3
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "welcome"; then
    echo "VERIFIED: Autopsy Welcome screen is visible"
else
    echo "WARNING: Welcome screen may have been dismissed"
fi

echo "=== Task setup complete ==="
echo "GT JPEG count: $(python3 -c "import json; d=json.load(open('/tmp/jpeg_evidence_gt.json')); print(d['total_jpegs'])" 2>/dev/null || echo '?')"
