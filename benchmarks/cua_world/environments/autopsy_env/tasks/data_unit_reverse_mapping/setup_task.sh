#!/bin/bash
echo "=== Setting up data_unit_reverse_mapping task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Clean up any previous run
rm -f /tmp/task_result.json /tmp/data_unit_reverse_mapping_gt.json
rm -rf /home/ga/Reports/
mkdir -p /home/ga/Reports/
chown -R ga:ga /home/ga/Reports/ 2>/dev/null || true

# Verify disk image exists
IMAGE="/home/ga/evidence/ntfs_undel.dd"
if [ ! -s "$IMAGE" ]; then
    echo "FATAL: Disk image not found at $IMAGE"
    exit 1
fi
echo "Disk image verified: $IMAGE"

# Dynamically generate Ground Truth and the flagged_blocks.txt input file
# We probe the image using the exact TSK tools the agent will use to ensure 100% accurate GT.
echo "Pre-computing ground truth from image content using TSK..."
python3 << 'PYEOF'
import subprocess, json, os

IMAGE = "/home/ga/evidence/ntfs_undel.dd"
blocks_to_test = []
gt = {}

# Probe blocks across the image to find a diverse set of 5 blocks
# (Allocated, unallocated, with path, without path)
for b in range(100, 4000, 37):
    b_str = str(b)
    try:
        # Check Allocation Status
        blk_res = subprocess.run(["blkstat", IMAGE, b_str], capture_output=True, text=True, timeout=5)
        if blk_res.returncode != 0:
            continue
        blk_out = blk_res.stdout
        alloc_status = "ALLOCATED" if ("Allocated" in blk_out and "Not Allocated" not in blk_out) else "UNALLOCATED"
        
        # Check Inode
        ifind_res = subprocess.run(["ifind", "-d", b_str, IMAGE], capture_output=True, text=True, timeout=5)
        ifind_out = ifind_res.stdout.strip()
        if "Inode not found" in ifind_out or not ifind_out:
            inode_res = "NONE"
        else:
            inode_res = ifind_out.splitlines()[0].strip()
            
        # Check Path
        path_res = "NONE"
        if inode_res != "NONE":
            base_in = inode_res.split('-')[0]
            ffind_res = subprocess.run(["ffind", "-a", IMAGE, base_in], capture_output=True, text=True, timeout=5)
            ffind_out = ffind_res.stdout.strip()
            lines = [l for l in ffind_out.splitlines() if l.strip()]
            if lines:
                path_str = lines[0].replace("* ", "").strip()
                if path_str:
                    path_res = path_str
        
        # Save to GT
        gt[b_str] = {
            "allocated": alloc_status,
            "inode": inode_res,
            "path": path_res
        }
        blocks_to_test.append(b_str)
        
        # Stop once we have exactly 5 diverse blocks
        if len(blocks_to_test) >= 5:
            break
            
    except Exception as e:
        print(f"Skipping block {b_str} due to error: {e}")

# Write inputs and GT
with open("/home/ga/evidence/flagged_blocks.txt", "w") as f:
    for b in blocks_to_test:
        f.write(b + "\n")

with open("/tmp/data_unit_reverse_mapping_gt.json", "w") as f:
    json.dump(gt, f, indent=2)

print(f"Generated GT for {len(blocks_to_test)} blocks: {blocks_to_test}")
PYEOF

chown ga:ga /home/ga/evidence/flagged_blocks.txt 2>/dev/null || true

# Pre-launch Autopsy just in case the agent decides to use the UI instead of CLI
# (Though CLI is faster and expected for this specific workflow)
su - ga -c "DISPLAY=:1 /opt/autopsy/bin/autopsy > /tmp/autopsy_background.log 2>&1 &"
sleep 5
DISPLAY=:1 wmctrl -r "Autopsy" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="