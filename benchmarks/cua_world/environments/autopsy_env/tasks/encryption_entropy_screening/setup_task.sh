#!/bin/bash
echo "=== Setting up encryption_entropy_screening task ==="

source /workspace/scripts/task_utils.sh

# ── Clean up stale artifacts ──────────────────────────────────────────────────
rm -f /tmp/encryption_screening_result.json /tmp/encryption_screening_gt.json \
      /tmp/encryption_screening_start_time 2>/dev/null || true

for d in /home/ga/Cases/Encryption_Screening_2024*/; do
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

# ── Pre-compute Ground Truth (Entropy for allocated files) ───────────────────
echo "Pre-computing file entropy ground truth..."
python3 << 'PYEOF'
import subprocess, json, re, math, os

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

allocated_files = []
for line in lines:
    stripped = re.sub(r'^[+\s]+', '', line)
    # Skip deleted files
    if ' * ' in stripped:
        continue
    m = re.match(r'^([\w/-]+)\s+(\d+)(?:-\S+)?:\s+(.+)', stripped)
    if not m:
        continue
    type_field = m.group(1)
    inode = m.group(2)
    name = m.group(3).strip()
    
    # Clean up names with tabs
    if '\t' in name:
        name = name.split('\t')[0].strip()
        
    # Only regular files (type ends with r)
    if type_field.endswith('d') or type_field.endswith('v'):
        continue
    # Skip standard metadata / current dir refs
    if name in ('.', '..') or name.startswith('$') or ':' in name:
        continue
        
    allocated_files.append({"name": name, "inode": inode})

print(f"Found {len(allocated_files)} allocated files. Computing entropy...")

gt_files = []
class_counts = {"LOW": 0, "MEDIUM": 0, "HIGH": 0, "SUSPICIOUS": 0}

for f in allocated_files:
    try:
        icat_result = subprocess.run(
            ["icat", IMAGE, f["inode"]],
            capture_output=True, timeout=5
        )
        data = icat_result.stdout
        
        if not data:
            ent = 0.0
        else:
            freq = [0] * 256
            for b in data:
                freq[b] += 1
            n = len(data)
            ent = -sum((c/n) * math.log2(c/n) for c in freq if c > 0)
        
        entropy_val = round(ent, 4)
        size_val = len(data)
        
        if entropy_val < 4.0:
            cls = "LOW"
        elif entropy_val < 6.5:
            cls = "MEDIUM"
        elif entropy_val < 7.5:
            cls = "HIGH"
        else:
            cls = "SUSPICIOUS"
            
        class_counts[cls] += 1
        
        gt_files.append({
            "name": f["name"],
            "inode": f["inode"],
            "size": size_val,
            "entropy": entropy_val,
            "classification": cls
        })
    except Exception as e:
        print(f"Failed to process {f['name']}: {e}")

gt = {
    "files": gt_files,
    "total_files": len(gt_files),
    "class_counts": class_counts
}

with open("/tmp/encryption_screening_gt.json", "w") as f:
    json.dump(gt, f, indent=2)

print(f"GT calculation complete. Analyzed {len(gt_files)} files.")
print(f"Classes: {class_counts}")
PYEOF

if [ ! -f /tmp/encryption_screening_gt.json ]; then
    echo "WARNING: GT computation failed. Creating empty fallback."
    echo '{"files":[],"total_files":0,"class_counts":{"LOW":0,"MEDIUM":0,"HIGH":0,"SUSPICIOUS":0}}' > /tmp/encryption_screening_gt.json
fi

# ── Record task start time ────────────────────────────────────────────────────
date +%s > /tmp/encryption_screening_start_time

# ── Kill any running Autopsy and relaunch ──────────────────────────────────────
kill_autopsy
sleep 2

echo "Launching Autopsy..."
launch_autopsy

echo "Waiting for Autopsy Welcome screen..."
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
    echo "ERROR: Autopsy Welcome screen did NOT appear."
    kill_autopsy; sleep 2; launch_autopsy
fi

sleep 3
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Setup complete ==="