#!/bin/bash
echo "=== Setting up NTFS ADS Concealment Detection task ==="

source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# ── Clean up stale artifacts ──────────────────────────────────────────────────
rm -f /tmp/ads_task_result.json 2>/dev/null || true
for d in /home/ga/Cases/ADS_Investigation_2024*/; do
    [ -d "$d" ] && rm -rf "$d" && echo "Removed old case: $d"
done

mkdir -p /home/ga/Reports
chown -R ga:ga /home/ga/Reports 2>/dev/null || true

# ── Generate Evidence Image with Concealed ADS ────────────────────────────────
mkdir -p /home/ga/evidence
IMAGE="/home/ga/evidence/suspect_drive.dd"
MNT_DIR="/tmp/mnt_ntfs_ads"

echo "Generating synthetic NTFS image with Alternate Data Streams..."
dd if=/dev/zero of="$IMAGE" bs=1M count=32 2>/dev/null
mkfs.ntfs -F -q -L "SUSPECT_USB" "$IMAGE"

mkdir -p "$MNT_DIR"
# Mount using ntfs-3g with streams_interface=xattr to allow ADS creation
if mount -t ntfs-3g -o loop,streams_interface=xattr "$IMAGE" "$MNT_DIR"; then
    echo "NTFS image mounted successfully. Injecting files..."
    
    # Create background noise
    for i in {1..30}; do
        echo "Standard innocuous file data for background noise. Sequence ID: $i" > "$MNT_DIR/document_$i.txt"
    done
    mkdir -p "$MNT_DIR/System" "$MNT_DIR/Downloads" "$MNT_DIR/Work"
    for i in {1..10}; do echo "Sys data" > "$MNT_DIR/System/sys_$i.dat"; done
    
    # Create target files and inject ADS using extended attributes
    python3 << 'PYEOF'
import os

mnt = "/tmp/mnt_ntfs_ads"

# Target 1: alpha_spec.txt -> config.ini
f1 = os.path.join(mnt, "Work", "alpha_spec.txt")
with open(f1, "w") as f:
    f.write("Project Alpha Specifications.\nOverview of the new UI changes.\n")
os.setxattr(f1, "user.config.ini", b"192.168.100.55")

# Target 2: hawaii_trip.txt -> wallet.dat
f2 = os.path.join(mnt, "Downloads", "hawaii_trip.txt")
with open(f2, "w") as f:
    f.write("Packing list for Hawaii:\n- Sunscreen\n- Swimsuit\n- Sunglasses\n")
os.setxattr(f2, "user.wallet.dat", b"abandon ability...")

# Target 3: backup.log -> service_cfg
f3 = os.path.join(mnt, "System", "backup.log")
with open(f3, "w") as f:
    f.write("Backup completed successfully at 02:00 AM.\nNo errors detected.\n")
os.setxattr(f3, "user.service_cfg", b"22222")
PYEOF

    sync
    umount "$MNT_DIR"
    rmdir "$MNT_DIR"
    echo "NTFS image successfully unmounted."
else
    echo "ERROR: Failed to loop-mount NTFS image. The task relies on loop-mount capabilities."
    exit 1
fi

chown ga:ga "$IMAGE"
chmod 644 "$IMAGE"
echo "Disk image ready: $IMAGE ($(stat -c%s "$IMAGE") bytes)"

# ── Launch Autopsy to ensure a clean starting state ───────────────────────────
kill_autopsy
echo "Launching Autopsy..."
launch_autopsy
wait_for_autopsy_window 120

# Maximize and focus Autopsy (Wait a bit for the Welcome window to appear)
sleep 10
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
WID=$(DISPLAY=:1 wmctrl -l | grep -i "autopsy" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Setup complete ==="