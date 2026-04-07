#!/bin/bash
# Setup script for forensic_peer_review_audit task

echo "=== Setting up forensic_peer_review_audit task ==="

source /workspace/scripts/task_utils.sh

# ── Clean up stale artifacts ──────────────────────────────────────────────────
rm -f /tmp/peer_review_result.json /tmp/peer_review_gt.json /tmp/peer_review_start_time 2>/dev/null || true

for d in /home/ga/Cases/Peer_Review_Audit_2024*/; do
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

# ── Generate deliberately flawed preliminary report ───────────────────────────
cat > /home/ga/evidence/preliminary_findings.txt << 'EOF'
PRELIMINARY FORENSIC FINDINGS
==============================
Analyst: J. Thompson (Junior Examiner)
Date: 2024-01-15
Image: ntfs_undel.dd

FILESYSTEM_TYPE: FAT32
VOLUME_LABEL: MY_USB_DRIVE
TOTAL_FILES: 25
TOTAL_DIRECTORIES: 8
DELETED_FILES: 2
ALLOCATED_FILES: 23
LARGEST_FILE_NAME: report.doc
LARGEST_FILE_SIZE: 500000

NOTES: Standard USB drive analysis. Filesystem appears to be FAT32.
Found 25 regular files, 2 of which were deleted. No unusual activity detected.
EOF
chown ga:ga /home/ga/evidence/preliminary_findings.txt

# ── Pre-compute Ground Truth using TSK ────────────────────────────────────────
echo "Pre-computing ground truth from TSK..."
python3 << 'PYEOF'
import subprocess, json

IMAGE = "/home/ga/evidence/ntfs_undel.dd"

def run_cmd(cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=30).stdout
    except Exception as e:
        print(f"Error running {' '.join(cmd)}: {e}")
        return ""

# Filesystem & Volume Label
fsstat_out = run_cmd(["fsstat", IMAGE])
fs_type = "NTFS" if "NTFS" in fsstat_out else "FAT" if "FAT" in fsstat_out else "Unknown"

vol_label = "No Label"
for line in fsstat_out.splitlines():
    if "Volume Name" in line or "Volume Label" in line:
        parts = line.split(":")
        if len(parts) > 1 and parts[1].strip():
            vol_label = parts[1].strip()

# File Counts
fls_all = run_cmd(["fls", "-r", IMAGE]).splitlines()
total_files = 0
deleted_files = 0
total_dirs = 0

for line in fls_all:
    # Basic directory count
    if " d/d " in line:
        total_dirs += 1
    # Regular file counts
    elif " r/r " in line or " -/r " in line:
        if " * " in line:
            deleted_files += 1
        else:
            total_files += 1

total_regular = total_files + deleted_files

gt = {
    "filesystem_type": fs_type,
    "volume_label": vol_label,
    "total_files": total_regular,
    "deleted_files": deleted_files,
    "allocated_files": total_files,
    "total_directories": total_dirs
}

with open("/tmp/peer_review_gt.json", "w") as f:
    json.dump(gt, f, indent=2)

print("Ground Truth computed:")
print(json.dumps(gt, indent=2))
PYEOF

# ── Record task start time ────────────────────────────────────────────────────
date +%s > /tmp/peer_review_start_time

# ── Kill any running Autopsy and relaunch ─────────────────────────────────────
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
    echo "ERROR: Autopsy Welcome screen did NOT appear."
fi

# Dismiss welcome screen safely
sleep 3
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Maximize Autopsy window
sleep 2
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "autopsy" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png ga

echo "=== Task setup complete ==="