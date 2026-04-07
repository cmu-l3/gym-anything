#!/bin/bash
# Setup script for ntfs_mft_data_run_mapping task

echo "=== Setting up ntfs_mft_data_run_mapping task ==="

source /workspace/scripts/task_utils.sh

# ── Clean up stale artifacts ──────────────────────────────────────────────────
rm -f /tmp/mft_data_run_result.json /tmp/mft_data_run_gt.json \
      /tmp/mft_data_run_start_time 2>/dev/null || true

# Remove previous case directories for this task
for d in /home/ga/Cases/MFT_Data_Run_Analysis*/; do
    [ -d "$d" ] && rm -rf "$d" && echo "Removed old case: $d"
done

# Create report directories
mkdir -p /home/ga/Reports
chown -R ga:ga /home/ga/Reports/ 2>/dev/null || true

# ── Verify disk image ─────────────────────────────────────────────────────────
IMAGE="/home/ga/evidence/ntfs_undel.dd"
if [ ! -s "$IMAGE" ]; then
    echo "ERROR: Disk image not found at $IMAGE"
    exit 1
fi
echo "Disk image: $IMAGE ($(stat -c%s "$IMAGE") bytes)"

# ── Pre-compute TSK ground truth (MFT Data Runs) ──────────────────────────────
echo "Pre-computing ground truth from TSK (istat)..."
python3 << 'PYEOF'
import subprocess, json, re

IMAGE = "/home/ga/evidence/ntfs_undel.dd"
gt_data = {}

try:
    # 1. Get all deleted files using fls
    proc = subprocess.run(["fls", "-r", "-d", IMAGE], capture_output=True, text=True, timeout=60)
    lines = proc.stdout.splitlines()

    files = []
    for line in lines:
        stripped = re.sub(r'^[+\s]+', '', line)
        m = re.match(r'^([\w/-]+)\s+\*\s+(\d+)(?:-\S+)?:\s+(.+)', stripped)
        if m:
            type_field = m.group(1)
            inode = m.group(2)
            name = m.group(3).strip()
            if '\t' in name:
                name = name.split('\t')[0].strip()
            # Skip directories and special files
            if type_field.endswith('d') or name.startswith('$') or name in ('.', '..'): 
                continue
            # Skip ADS
            if ':' in name:
                continue
            files.append((inode, name))

    # 2. Parse istat for each file to get $DATA residency and runs
    for inode, name in files:
        if inode in gt_data: 
            continue # Avoid duplicate processing
            
        iproc = subprocess.run(["istat", IMAGE, inode], capture_output=True, text=True, timeout=10)
        istat_out = iproc.stdout

        # Find primary unnamed $DATA attribute
        # Looking for "Type: $DATA (128)   Name: $Data"
        data_attr_idx = istat_out.find("Type: $DATA")
        if data_attr_idx == -1: 
            continue

        data_section = istat_out[data_attr_idx:]
        next_attr_idx = data_section.find("Type: ", 1)
        if next_attr_idx != -1:
            data_section = data_section[:next_attr_idx]

        residency = "UNKNOWN"
        start_cluster = "N/A"
        cluster_length = "N/A"

        if "Resident" in data_section and "Non-Resident" not in data_section:
            residency = "RESIDENT"
        elif "Non-Resident" in data_section:
            residency = "NON_RESIDENT"
            
            # Extract Data Runs. Example format:
            # Data Runs:
            #   0:      400508 to      400510 (3)
            # or sometimes just:   0:      400508 (1)
            match = re.search(r'0:\s+(\d+)\s+to\s+\d+\s+\((\d+)\)', data_section)
            if match:
                start_cluster = match.group(1)
                cluster_length = match.group(2)
            else:
                match_single = re.search(r'0:\s+(\d+)\s+\((\d+)\)', data_section)
                if match_single:
                    start_cluster = match_single.group(1)
                    cluster_length = match_single.group(2)

        gt_data[inode] = {
            "name": name,
            "residency": residency,
            "start_cluster": start_cluster,
            "cluster_length": cluster_length
        }

    # Save Ground Truth
    with open("/tmp/mft_data_run_gt.json", "w") as f:
        json.dump(gt_data, f, indent=2)

    print(f"Ground truth: {len(gt_data)} deleted files analyzed")
    for inode, info in list(gt_data.items())[:5]:
        print(f"  inode={inode}: {info['residency']}, start={info['start_cluster']}, len={info['cluster_length']}")

except Exception as e:
    print(f"WARNING: Ground truth generation failed: {e}")
    with open("/tmp/mft_data_run_gt.json", "w") as f:
        json.dump({}, f)
PYEOF

# ── Record task start time ────────────────────────────────────────────────────
date +%s > /tmp/mft_data_run_start_time

# ── Kill any running Autopsy and relaunch ─────────────────────────────────────
kill_autopsy
sleep 2

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
done

if [ "$WELCOME_FOUND" = false ]; then
    echo "ERROR: Autopsy Welcome screen did NOT appear."
fi

# Ensure window is maximized
DISPLAY=:1 wmctrl -r "Welcome" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -r "Autopsy" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="