#!/bin/bash
echo "=== Setting up IP Theft Source Code Triage task ==="

source /workspace/scripts/task_utils.sh

# 1. Clean up stale artifacts and old cases
rm -f /tmp/ip_theft_result.json /tmp/ip_theft_gt.json /tmp/task_start_time 2>/dev/null || true
rm -rf /home/ga/Cases/IP_Theft_2024* 2>/dev/null || true
mkdir -p /home/ga/Reports
chown -R ga:ga /home/ga/Reports 2>/dev/null || true

# 2. Synthesize realistic evidence using real source code (Redis 6.2.6)
echo "Generating realistic IP theft disk image..."
mkdir -p /home/ga/evidence
IMAGE="/home/ga/evidence/ip_theft.dd"
STAGING="/tmp/ip_theft_staging"
rm -rf "$STAGING" && mkdir -p "$STAGING"

# Create target and decoy directories
mkdir -p "$STAGING/Personal/Projects/Archived"
mkdir -p "$STAGING/Documents/Learning/C_Tutorials"

# Download a real C project (Redis) to serve as the proprietary IP
echo "Downloading source code..."
wget -qO /tmp/redis.tar.gz https://download.redis.io/releases/redis-6.2.6.tar.gz
tar -xzf /tmp/redis.tar.gz -C "$STAGING/Personal/Projects/Archived/"
mv "$STAGING/Personal/Projects/Archived/redis-6.2.6" "$STAGING/Personal/Projects/Archived/AcmeDB_Core"

# Move a subset of files to the decoy directory (Lua deps) and remove them from the target
echo "Setting up decoy files..."
mv "$STAGING/Personal/Projects/Archived/AcmeDB_Core/deps/lua/src/"*.c "$STAGING/Documents/Learning/C_Tutorials/"
mv "$STAGING/Personal/Projects/Archived/AcmeDB_Core/deps/lua/src/"*.h "$STAGING/Documents/Learning/C_Tutorials/" 2>/dev/null || true
rm -rf "$STAGING/Personal/Projects/Archived/AcmeDB_Core/deps/lua"

# Create FAT32 Disk Image
echo "Creating disk image..."
dd if=/dev/zero of="$IMAGE" bs=1M count=120 status=none
mkfs.vfat -F 32 -n "BACKUP_DRV" "$IMAGE" > /dev/null

# Mount and copy files
MNT="/tmp/mnt_ip_theft"
sudo mkdir -p "$MNT"
sudo mount -o loop "$IMAGE" "$MNT"
sudo cp -r "$STAGING"/* "$MNT"/
sudo umount "$MNT"
chown ga:ga "$IMAGE"

# 3. Pre-compute Ground Truth (MD5 hashes for target vs decoy)
echo "Pre-computing ground truth..."
python3 << 'PYEOF'
import os, hashlib, json

STAGING = "/tmp/ip_theft_staging"
TARGET_DIR = os.path.join(STAGING, "Personal/Projects/Archived/AcmeDB_Core")
DECOY_DIR = os.path.join(STAGING, "Documents/Learning/C_Tutorials")

def hash_files_in_dir(directory):
    file_info = {}
    for root, _, files in os.walk(directory):
        for f in files:
            if f.endswith('.c') or f.endswith('.h'):
                path = os.path.join(root, f)
                with open(path, 'rb') as fp:
                    content = fp.read()
                    md5 = hashlib.md5(content).hexdigest().lower()
                    size = len(content)
                    # Use hash as key to handle duplicates
                    file_info[md5] = {
                        "name": f,
                        "size": size,
                        "rel_path": os.path.relpath(path, STAGING)
                    }
    return file_info

target_files = hash_files_in_dir(TARGET_DIR)
decoy_files = hash_files_in_dir(DECOY_DIR)

gt = {
    "target_files": target_files,
    "target_count": len(target_files),
    "target_size_bytes": sum(f["size"] for f in target_files.values()),
    "decoy_files": decoy_files,
    "decoy_count": len(decoy_files)
}

with open("/tmp/ip_theft_gt.json", "w") as fp:
    json.dump(gt, fp, indent=2)

print(f"Ground Truth: {gt['target_count']} target files, {gt['decoy_count']} decoy files.")
PYEOF

# Clean up staging
rm -rf "$STAGING" /tmp/redis.tar.gz

# 4. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time

# 5. Relaunch Autopsy cleanly
kill_autopsy
launch_autopsy

echo "Waiting for Autopsy window..."
wait_for_autopsy_window 120

DISPLAY=:1 xdotool key Escape 2>/dev/null || true
DISPLAY=:1 wmctrl -r "Autopsy" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 6. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="