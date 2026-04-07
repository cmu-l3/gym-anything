#!/bin/bash
# Setup script for extension_mismatch_detection task

echo "=== Setting up extension_mismatch_detection task ==="

source /workspace/scripts/task_utils.sh

# ── Clean up stale artifacts ──────────────────────────────────────────────────
rm -f /tmp/extension_mismatch_result.json /tmp/extension_mismatch_gt.json \
      /tmp/task_start_time.txt 2>/dev/null || true

# Remove previous case directories
for d in /home/ga/Cases/Extension_Mismatch_2024*/; do
    [ -d "$d" ] && rm -rf "$d" && echo "Removed old case: $d"
done

# Prepare Reports directory
mkdir -p /home/ga/Reports
chown -R ga:ga /home/ga/Reports/ 2>/dev/null || true

# ── Verify disk image ─────────────────────────────────────────────────────────
IMAGE="/home/ga/evidence/jpeg_search.dd"
if [ ! -s "$IMAGE" ]; then
    echo "WARNING: jpeg_search.dd not found, attempting to use ntfs_undel.dd"
    IMAGE="/home/ga/evidence/ntfs_undel.dd"
fi
if [ ! -s "$IMAGE" ]; then
    echo "ERROR: Disk image not found at $IMAGE"
    exit 1
fi
echo "Disk image: $IMAGE ($(stat -c%s "$IMAGE") bytes)"

# ── Pre-compute Ground Truth (Extension Mismatches) ───────────────────────────
echo "Pre-computing extension mismatch ground truth using TSK..."
python3 << 'PYEOF'
import subprocess, json, re, sys, os

IMAGE = sys.argv[1] if len(sys.argv) > 1 else "/home/ga/evidence/jpeg_search.dd"
if not os.path.exists(IMAGE):
    IMAGE = "/home/ga/evidence/ntfs_undel.dd"

# Very basic extension to MIME type map to simulate Autopsy's logic
EXT_TO_MIME = {
    "jpg": "image/jpeg", "jpeg": "image/jpeg",
    "png": "image/png", "gif": "image/gif",
    "txt": "text/plain", "log": "text/plain",
    "pdf": "application/pdf", "doc": "application/msword",
    "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    "zip": "application/zip", "rar": "application/x-rar-compressed"
}

try:
    result = subprocess.run(
        ["fls", "-r", IMAGE],
        capture_output=True, text=True, timeout=60
    )
    lines = result.stdout.splitlines()
except Exception as e:
    print(f"WARNING: fls failed: {e}")
    lines = []

mismatches = []
total_files = 0

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

    total_files += 1

    # Extract extension
    ext = ""
    dot_pos = name.rfind('.')
    if dot_pos >= 0 and dot_pos < len(name) - 1:
        ext = name[dot_pos+1:].lower()
        
    # Ignore files without extensions for this specific anti-forensics task
    if not ext:
        continue

    # Use icat + file to detect actual MIME type
    try:
        icat_proc = subprocess.Popen(["icat", IMAGE, inode], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        file_proc = subprocess.Popen(["file", "-b", "--mime-type", "-"], stdin=icat_proc.stdout, stdout=subprocess.PIPE, text=True)
        icat_proc.stdout.close()
        actual_mime = file_proc.communicate()[0].strip()
        
        # Determine if there's a mismatch
        expected_mime = EXT_TO_MIME.get(ext)
        
        # Mismatch logic: If extension implies plain text but actual is image, etc.
        # Autopsy marks mismatches when actual MIME strongly disagrees with expected
        is_mismatch = False
        if expected_mime and expected_mime != actual_mime:
            # Avoid penalizing generic octet-stream differences
            if not actual_mime.startswith("application/octet-stream") and not actual_mime.startswith("inode/"):
                is_mismatch = True
        elif not expected_mime:
            # If extension is weird (e.g., .dat) but content is an image/jpeg
            if actual_mime.startswith("image/") or actual_mime == "application/pdf":
                if ext not in ["dat", "bin"]: # common generic exts
                    is_mismatch = True
                else:
                    # Treat disguised generic extensions as mismatches if they hide media
                    is_mismatch = True
                    
        if is_mismatch:
            mismatches.append({
                "name": name,
                "inode": inode,
                "ext": ext,
                "actual_mime": actual_mime,
                "expected_mime": expected_mime
            })
    except Exception as e:
        pass

gt = {
    "total_files_scanned": total_files,
    "total_mismatches": len(mismatches),
    "mismatched_files": mismatches,
    "mismatched_names": [m["name"] for m in mismatches],
    "image_path": IMAGE
}

with open("/tmp/extension_mismatch_gt.json", "w") as f:
    json.dump(gt, f, indent=2)

print(f"Ground truth: Scanned {total_files} files, found {len(mismatches)} mismatches")
for m in mismatches:
    print(f"  [Mismatch] {m['name']} (ext: {m['ext']} -> {m['actual_mime']})")
PYEOF

if [ ! -f /tmp/extension_mismatch_gt.json ]; then
    echo "WARNING: Ground truth computation failed, creating empty GT"
    echo '{"total_files_scanned":0,"total_mismatches":0,"mismatched_files":[],"mismatched_names":[]}' > /tmp/extension_mismatch_gt.json
fi

# ── Record task start time ────────────────────────────────────────────────────
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# ── Kill any running Autopsy ──────────────────────────────────────────────────
kill_autopsy

# ── Launch Autopsy and wait for Welcome screen ────────────────────────────────
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
    kill_autopsy
    sleep 2
    launch_autopsy
    FINAL_ELAPSED=0
    while [ $FINAL_ELAPSED -lt 120 ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "welcome"; then
            echo "Welcome screen appeared on retry after additional ${FINAL_ELAPSED}s"
            WELCOME_FOUND=true
            break
        fi
        DISPLAY=:1 xdotool mousemove 960 540 click 1 2>/dev/null || true
        sleep 5
        FINAL_ELAPSED=$((FINAL_ELAPSED + 5))
    done
fi

sleep 3
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take an initial screenshot
take_screenshot /tmp/task_initial.png ga

echo "=== Task setup complete ==="