#!/bin/bash
echo "=== Setting up ntfs_time_stomping_data_run_analysis task ==="

source /workspace/scripts/task_utils.sh

# ── 1. Clean up stale artifacts ───────────────────────────────────────────────
rm -f /tmp/mft_analysis_result.json /tmp/mft_analysis_gt.json \
      /tmp/mft_task_start_time 2>/dev/null || true

for d in /home/ga/Cases/MFT_Analysis_2024*/; do
    [ -d "$d" ] && rm -rf "$d" && echo "Removed old case: $d"
done

mkdir -p /home/ga/Reports
chown -R ga:ga /home/ga/Reports/ 2>/dev/null || true

# ── 2. Verify disk image ──────────────────────────────────────────────────────
IMAGE="/home/ga/evidence/ntfs_undel.dd"
if [ ! -s "$IMAGE" ]; then
    echo "ERROR: Disk image not found at $IMAGE"
    exit 1
fi
echo "Disk image: $IMAGE ($(stat -c%s "$IMAGE") bytes)"

# ── 3. Pre-compute Ground Truth (Top 5 Deleted Files via TSK) ─────────────────
echo "Pre-computing ground truth from TSK..."
python3 << 'PYEOF'
import subprocess, json, re, sys

IMAGE = "/home/ga/evidence/ntfs_undel.dd"

# 1. Enumerate deleted files
try:
    fls_out = subprocess.check_output(["fls", "-r", "-d", IMAGE], text=True, timeout=60)
except Exception as e:
    print(f"WARNING: fls failed: {e}")
    fls_out = ""

deleted_files = []
for line in fls_out.splitlines():
    stripped = re.sub(r'^[+\s]+', '', line)
    # Match: TYPE * INODE[-attr]: NAME
    m = re.match(r'^([\w/-]+)\s+\*\s+(\d+)(?:-\S+)?:\s+(.+)', stripped)
    if not m: continue
    type_f, inode, name = m.groups()
    name = name.split('\t')[0].strip()
    
    # Skip directories and system files
    if type_f.endswith('d') or type_f.endswith('v'): continue
    if name in ('.', '..') or ':' in name or name.startswith('$'): continue
    
    deleted_files.append({"inode": inode, "name": name})

# 2. Extract precise MFT metadata for each using istat
results = []
for f in deleted_files:
    try:
        istat_out = subprocess.check_output(["istat", IMAGE, f["inode"]], text=True, timeout=5)
    except Exception:
        continue
    
    # Parse Size
    size_m = re.search(r'Size:\s+(\d+)', istat_out)
    size = int(size_m.group(1)) if size_m else 0
    
    sia_c, fna_c = "NONE", "NONE"
    d_start, d_len = "NONE", "NONE"
    in_sia, in_fna, in_runs = False, False, False
    
    for line in istat_out.splitlines():
        line = line.strip()
        if line.startswith("$STANDARD_INFORMATION"):
            in_sia, in_fna = True, False
        elif line.startswith("$FILE_NAME"):
            if fna_c == "NONE": in_fna = True
            in_sia = False
        elif line.startswith("$DATA") or line.startswith("Type:"):
            in_sia, in_fna, in_runs = False, False, False
            
        if in_sia and line.startswith("Created:"):
            m2 = re.search(r'Created:\s*(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})', line)
            if m2: sia_c = m2.group(1)
            
        if in_fna and line.startswith("Created:"):
            m2 = re.search(r'Created:\s*(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})', line)
            if m2: fna_c = m2.group(1)
            
        if "Data Runs:" in line:
            in_runs = True
        elif in_runs:
            if not line: 
                in_runs = False
            else:
                parts = line.split()
                if len(parts) >= 2:
                    d_start, d_len = parts[0], parts[1]
                in_runs = False
                
    results.append({
        "inode": f["inode"],
        "name": f["name"],
        "size": size,
        "sia": sia_c,
        "fna": fna_c,
        "run_start": d_start,
        "run_len": d_len
    })

# 3. Sort by Size (DESC) then Inode (ASC)
results.sort(key=lambda x: (-x["size"], int(x["inode"].split('-')[0] if '-' in x["inode"] else x["inode"])))
top_5 = results[:5]

gt = {
    "total_deleted_evaluated": len(results),
    "top_5": top_5,
    "top_5_inodes": [x["inode"] for x in top_5]
}

with open("/tmp/mft_analysis_gt.json", "w") as f:
    json.dump(gt, f, indent=2)

print(f"Ground Truth Computed: Found {len(results)} valid deleted files.")
for t in top_5:
    print(f"  -> Inode {t['inode']}: {t['name']} ({t['size']} bytes)")
PYEOF

# ── 4. Setup application state ────────────────────────────────────────────────
# Record task start time (for anti-gaming detection)
date +%s > /tmp/mft_task_start_time

kill_autopsy
echo "Launching Autopsy..."
launch_autopsy
wait_for_autopsy_window 300

# Handle Welcome Screen Dismissal
WELCOME_ELAPSED=0
WELCOME_FOUND=false
while [ $WELCOME_ELAPSED -lt 300 ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "welcome"; then
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
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Capture initial state
take_screenshot /tmp/task_initial_state.png ga

echo "=== Task setup complete ==="