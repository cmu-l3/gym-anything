#!/bin/bash
# Setup script for split_image_anti_forensics_reconstruction task

echo "=== Setting up split_image_anti_forensics task ==="

source /workspace/scripts/task_utils.sh

# ── Clean up stale artifacts ──────────────────────────────────────────────────
rm -f /tmp/reconstruction_result.json /tmp/reconstruction_gt.json \
      /tmp/reconstruction_start_time 2>/dev/null || true

for d in /home/ga/Cases/Fragment_Recovery_2024*/; do
    [ -d "$d" ] && rm -rf "$d" && echo "Removed old case: $d"
done

mkdir -p /home/ga/Reports
chown -R ga:ga /home/ga/Reports/ 2>/dev/null || true

# ── Verify base disk image ────────────────────────────────────────────────────
IMAGE="/home/ga/evidence/ntfs_undel.dd"
if [ ! -s "$IMAGE" ]; then
    echo "ERROR: Base disk image not found at $IMAGE"
    exit 1
fi

TOTAL_SIZE=$(stat -c%s "$IMAGE")
echo "Base disk image: $IMAGE ($TOTAL_SIZE bytes)"

if [ "$TOTAL_SIZE" -le 3072000 ]; then
    echo "ERROR: Base image is too small to split at 3072000 bytes."
    exit 1
fi

# ── Create fragmented evidence ────────────────────────────────────────────────
echo "Splitting image into fragments..."
dd if="$IMAGE" of="/home/ga/evidence/frag.001" bs=1000 count=3072 2>/dev/null
dd if="$IMAGE" of="/home/ga/evidence/system_backup.bak" bs=1000 skip=3072 2>/dev/null

chown ga:ga /home/ga/evidence/frag.001 /home/ga/evidence/system_backup.bak
chmod 644 /home/ga/evidence/frag.001 /home/ga/evidence/system_backup.bak

# ── Pre-compute Ground Truth (GT) ─────────────────────────────────────────────
echo "Pre-computing ground truth via TSK..."
python3 << 'PYEOF'
import subprocess, json, re, hashlib

IMAGE = "/home/ga/evidence/ntfs_undel.dd"
SPLIT_BYTE = 3072000

# 1. Compute original MD5 & size
with open(IMAGE, 'rb') as f:
    data = f.read()
    md5_orig = hashlib.md5(data).hexdigest()
    size_orig = len(data)

# 2. Get Block Size
try:
    fsstat = subprocess.check_output(['fsstat', IMAGE], timeout=10).decode(errors='ignore')
    block_size = 512
    for line in fsstat.splitlines():
        if "Cluster Size:" in line or "Block Size:" in line:
            block_size = int(line.split(":")[1].strip())
            break
except Exception as e:
    print(f"WARNING: fsstat failed, defaulting to 512. {e}")
    block_size = 512

target_block = SPLIT_BYTE // block_size

# 3. Enumerate allocated files
try:
    fls = subprocess.check_output(['fls', '-r', IMAGE], timeout=30).decode(errors='ignore')
except Exception as e:
    print(f"WARNING: fls failed: {e}")
    fls = ""

allocated_files = []
for line in fls.splitlines():
    if " * " in line: continue  # Skip deleted
    # Remove nested prefixes
    stripped = re.sub(r'^[+\s]+', '', line)
    # Match TYPE INODE: NAME
    m = re.match(r'^([\w/-]+)\s+(\d+)(?:-\S+)?:\s+(.+)', stripped)
    if not m: continue
    
    type_field = m.group(1)
    inode = m.group(2)
    name = m.group(3).strip()
    
    if type_field.endswith('d') or type_field.endswith('v'): continue
    if name in ('.', '..') or name.startswith('$') or ':' in name: continue
    
    allocated_files.append({"inode": inode, "name": name})

# 4. Check block runs for Non-Resident files
hidden_files = []
for f in allocated_files:
    try:
        istat = subprocess.check_output(['istat', IMAGE, f['inode']], timeout=5).decode(errors='ignore')
        if "Non-Resident" in istat:
            blocks = []
            data_section = False
            for line in istat.splitlines():
                if "Type: $DATA" in line:
                    data_section = True
                elif "Type: $" in line and data_section:
                    data_section = False
                
                if data_section and "Non-Resident" not in line and "size:" not in line and "init_size:" not in line:
                    # Look for numbers
                    for token in line.split():
                        if '-' in token:
                            rng = token.split('-')
                            if len(rng) == 2 and rng[0].isdigit() and rng[1].isdigit():
                                if int(rng[1]) >= target_block:
                                    blocks.append(int(rng[1]))
                        elif token.isdigit():
                            if int(token) >= target_block:
                                blocks.append(int(token))
            
            if blocks:
                hidden_files.append({"inode": f['inode'], "name": f['name']})
    except Exception:
        continue

# 5. Save GT
gt = {
    "original_md5": md5_orig,
    "original_size": size_orig,
    "block_size": block_size,
    "target_block": target_block,
    "hidden_files": hidden_files,
    "hidden_inodes": [f['inode'] for f in hidden_files]
}

with open("/tmp/reconstruction_gt.json", "w") as f:
    json.dump(gt, f, indent=2)

print(f"Ground Truth: Size={size_orig}, MD5={md5_orig}")
print(f"Filesystem block size={block_size}, Target Block={target_block}")
print(f"Found {len(hidden_files)} files in hidden chunk.")
PYEOF

# ── Remove original to force reconstruction ───────────────────────────────────
rm -f "$IMAGE"
echo "Original image removed. Fragments ready."

# ── Record start time & launch ────────────────────────────────────────────────
date +%s > /tmp/reconstruction_start_time

kill_autopsy
echo "Launching Autopsy..."
launch_autopsy
wait_for_autopsy_window 120

# Dismiss any popup dialogs
sleep 5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png ga
echo "=== Setup Complete ==="