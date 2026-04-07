#!/bin/bash
# Setup script for custom_interesting_items_triage task

echo "=== Setting up custom_interesting_items_triage task ==="

source /workspace/scripts/task_utils.sh

# ── Clean up stale artifacts ──────────────────────────────────────────────────
rm -f /tmp/triage_result.json /tmp/triage_gt.json /tmp/triage_start_time 2>/dev/null || true

for d in /home/ga/Cases/Targeted_Triage_2024*/; do
    [ -d "$d" ] && rm -rf "$d" && echo "Removed old case: $d"
done

# Clear any previously saved Interesting Item rules in Autopsy user config
rm -f /home/ga/.autopsy/dev/config/Preferences/org/sleuthkit/autopsy/modules/interestingitems/*.xml 2>/dev/null || true

mkdir -p /home/ga/Reports
chown -R ga:ga /home/ga/Reports/ 2>/dev/null || true

# ── Verify disk image ─────────────────────────────────────────────────────────
IMAGE="/home/ga/evidence/ntfs_undel.dd"
if [ ! -s "$IMAGE" ]; then
    echo "ERROR: Disk image not found at $IMAGE"
    exit 1
fi
echo "Disk image: $IMAGE ($(stat -c%s "$IMAGE") bytes)"

# ── Pre-compute TSK ground truth (Target files) ───────────────────────────────
echo "Pre-computing ground truth from TSK..."
python3 << 'PYEOF'
import subprocess, json, re, hashlib

IMAGE = "/home/ga/evidence/ntfs_undel.dd"
TARGET_EXTS = {".txt", ".log", ".xml"}

try:
    result = subprocess.run(
        ["fls", "-r", IMAGE],
        capture_output=True, text=True, timeout=60
    )
    lines = result.stdout.splitlines()
except Exception as e:
    print(f"WARNING: fls failed: {e}")
    lines = []

target_files = []
for line in lines:
    stripped = re.sub(r'^[+\s]+', '', line)
    is_deleted = ' * ' in stripped
    m = re.match(r'^([\w/-]+)\s+(?:\*\s+)?(\d+)(?:-\S+)?:\s+(.+)', stripped)
    if not m:
        continue
    type_field = m.group(1)
    inode = m.group(2)
    name = m.group(3).strip()
    if '\t' in name:
        name = name.split('\t')[0].strip()
        
    if type_field.endswith('d') or type_field.endswith('v'):
        continue
    if name in ('.', '..') or name.startswith('$') or ':' in name:
        continue
        
    ext = ""
    dot_pos = name.rfind('.')
    if dot_pos >= 0:
        ext = name[dot_pos:].lower()
        
    if ext in TARGET_EXTS:
        target_files.append({
            "name": name,
            "inode": inode,
            "ext": ext.lstrip('.'),
            "deleted": is_deleted
        })

# Compute MD5s using icat
for f in target_files:
    try:
        icat_result = subprocess.run(
            ["icat", IMAGE, f["inode"]],
            capture_output=True, timeout=5
        )
        if icat_result.returncode == 0 and icat_result.stdout:
            f["md5"] = hashlib.md5(icat_result.stdout).hexdigest()
            f["size"] = len(icat_result.stdout)
        else:
            f["md5"] = "N/A"
            f["size"] = 0
    except Exception:
        f["md5"] = "N/A"
        f["size"] = 0

gt = {
    "total_targets": len(target_files),
    "txt_count": sum(1 for f in target_files if f["ext"] == "txt"),
    "log_count": sum(1 for f in target_files if f["ext"] == "log"),
    "xml_count": sum(1 for f in target_files if f["ext"] == "xml"),
    "target_files": target_files,
    "target_names": [f["name"] for f in target_files],
    "image_path": IMAGE
}

with open("/tmp/triage_gt.json", "w") as f:
    json.dump(gt, f, indent=2)

print(f"Ground truth: {gt['total_targets']} target files found")
print(f"  TXT: {gt['txt_count']}, LOG: {gt['log_count']}, XML: {gt['xml_count']}")
PYEOF

if [ ! -f /tmp/triage_gt.json ]; then
    echo "WARNING: Ground truth computation failed, creating empty GT"
    echo '{"total_targets":0,"target_files":[],"target_names":[]}' > /tmp/triage_gt.json
fi

# ── Record task start time ────────────────────────────────────────────────────
date +%s > /tmp/triage_start_time
echo "Task start time recorded: $(cat /tmp/triage_start_time)"

# ── Kill any running Autopsy ──────────────────────────────────────────────────
kill_autopsy

# ── Launch Autopsy and wait for Welcome screen ────────────────────────────────
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
    echo "ERROR: Autopsy Welcome screen did NOT appear within ${WELCOME_TIMEOUT}s"
    kill_autopsy
    sleep 2
    launch_autopsy
    sleep 30
fi

# Dismiss popups
sleep 3
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="