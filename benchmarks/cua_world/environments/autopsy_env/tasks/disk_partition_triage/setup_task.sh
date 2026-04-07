#!/bin/bash
# Setup script for disk_partition_triage task

echo "=== Setting up disk_partition_triage task ==="

source /workspace/scripts/task_utils.sh

# ── Clean up stale artifacts ──────────────────────────────────────────────────
rm -f /tmp/disk_triage_result.json /tmp/disk_triage_gt.json \
      /tmp/disk_triage_start_time 2>/dev/null || true

# Remove previous case directories for this task
for d in /home/ga/Cases/Disk_Triage_2024*/; do
    [ -d "$d" ] && rm -rf "$d" && echo "Removed old case: $d"
done

# Create report output directories
mkdir -p /home/ga/Reports
chown -R ga:ga /home/ga/Reports/ 2>/dev/null || true

# ── Verify disk image ─────────────────────────────────────────────────────────
IMAGE="/home/ga/evidence/ntfs_undel.dd"
if [ ! -s "$IMAGE" ]; then
    echo "ERROR: Disk image not found at $IMAGE"
    exit 1
fi
echo "Disk image: $IMAGE ($(stat -c%s "$IMAGE") bytes)"

# ── Pre-compute TSK ground truth (File System & Volume Data) ────────────────
echo "Pre-computing ground truth from TSK..."
python3 << 'PYEOF'
import subprocess, json, re, os, sys

IMAGE = "/home/ga/evidence/ntfs_undel.dd"

gt = {
    "image_path": IMAGE,
    "image_size_bytes": os.path.getsize(IMAGE),
    "file_system_type": "UNKNOWN",
    "volume_name": "NONE",
    "sector_size": 0,
    "cluster_size": 0,
    "total_sectors": 0,
    "total_clusters": 0,
    "total_files": 0,
    "total_directories": 0,
    "deleted_files": 0,
    "allocated_files": 0,
    "partitions": []
}

# 1. fsstat for Volume metadata
try:
    fs_res = subprocess.run(["fsstat", IMAGE], capture_output=True, text=True, timeout=10)
    fs_out = fs_res.stdout
    
    # File System Type
    m = re.search(r'File System Type:\s*(.+)', fs_out)
    if m: gt["file_system_type"] = m.group(1).strip()
    
    # Volume Name
    m = re.search(r'Volume Name:\s*(.+)', fs_out)
    if m: gt["volume_name"] = m.group(1).strip()
    
    # Sector Size
    m = re.search(r'Sector Size:\s*(\d+)', fs_out)
    if m: gt["sector_size"] = int(m.group(1))
    
    # Cluster Size
    m = re.search(r'Cluster Size:\s*(\d+)', fs_out)
    if m: gt["cluster_size"] = int(m.group(1))
    
    # Total Sectors (upper bound of range + 1)
    m = re.search(r'Total Sector Range:\s*\d+\s+-\s+(\d+)', fs_out)
    if m: gt["total_sectors"] = int(m.group(1)) + 1
    
    # Total Clusters
    m = re.search(r'Total Cluster Range:\s*\d+\s+-\s+(\d+)', fs_out)
    if m: gt["total_clusters"] = int(m.group(1)) + 1

except Exception as e:
    print(f"WARNING: fsstat failed: {e}")

# Hardcode fallback for standard NTFS image if fsstat parsing failed
if gt["file_system_type"] == "UNKNOWN":
    gt["file_system_type"] = "NTFS"
    gt["sector_size"] = 512

# 2. mmls for Partition Table
try:
    mmls_res = subprocess.run(["mmls", IMAGE], capture_output=True, text=True, timeout=10)
    for line in mmls_res.stdout.splitlines():
        # Match: 000:  Meta      0000000000   0000000000   0000000001   Primary Table (#0)
        m = re.match(r'^\s*(\d+):\s+(\w+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(.+)', line)
        if m:
            gt["partitions"].append({
                "index": int(m.group(1)),
                "offset": int(m.group(3)),
                "length": int(m.group(5)),
                "desc": m.group(6).strip()
            })
except Exception as e:
    print(f"WARNING: mmls failed: {e}")

# 3. fls for File Statistics
try:
    fls_res = subprocess.run(["fls", "-r", IMAGE], capture_output=True, text=True, timeout=60)
    for line in fls_res.stdout.splitlines():
        stripped = re.sub(r'^[+\s]+', '', line)
        is_deleted = ' * ' in stripped
        m = re.match(r'^([\w/-]+)\s+(?:\*\s+)?(\d+)(?:-\S+)?:\s+(.+)', stripped)
        if not m: continue
        
        type_field = m.group(1)
        name = m.group(3).strip()
        
        # Skip pseudo-entries
        if name in ('.', '..'): continue
        
        if type_field.endswith('d'):
            gt["total_directories"] += 1
        else:
            gt["total_files"] += 1
            if is_deleted:
                gt["deleted_files"] += 1
            else:
                gt["allocated_files"] += 1
                
except Exception as e:
    print(f"WARNING: fls failed: {e}")

with open("/tmp/disk_triage_gt.json", "w") as f:
    json.dump(gt, f, indent=2)

print(json.dumps(gt, indent=2))
PYEOF

if [ ! -f /tmp/disk_triage_gt.json ]; then
    echo "WARNING: GT computation failed, creating dummy GT"
    echo '{"file_system_type":"NTFS","sector_size":512}' > /tmp/disk_triage_gt.json
fi

# ── Record task start time ────────────────────────────────────────────────────
date +%s > /tmp/disk_triage_start_time
echo "Task start time recorded: $(cat /tmp/disk_triage_start_time)"

# ── Kill any running Autopsy and relaunch ─────────────────────────────────────
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
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 5
    WELCOME_ELAPSED=$((WELCOME_ELAPSED + 5))
    if [ $((WELCOME_ELAPSED % 60)) -eq 0 ]; then
        if ! pgrep -f "/opt/autopsy" >/dev/null 2>&1; then
            echo "Autopsy died, relaunching at ${WELCOME_ELAPSED}s..."
            launch_autopsy
        fi
    fi
done

if [ "$WELCOME_FOUND" = false ]; then
    echo "ERROR: Autopsy Welcome screen did NOT appear within ${WELCOME_TIMEOUT}s"
    kill_autopsy; sleep 2; launch_autopsy
    FINAL_ELAPSED=0
    while [ $FINAL_ELAPSED -lt 120 ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "welcome"; then
            echo "Welcome screen appeared on retry"
            WELCOME_FOUND=true
            break
        fi
        DISPLAY=:1 xdotool mousemove 960 540 click 1 2>/dev/null || true
        sleep 5; FINAL_ELAPSED=$((FINAL_ELAPSED + 5))
    done
fi

sleep 3
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png ga

echo "=== Task setup complete ==="