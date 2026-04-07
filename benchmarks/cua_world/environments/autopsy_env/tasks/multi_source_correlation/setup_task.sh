#!/bin/bash
# Setup script for multi_source_correlation task

echo "=== Setting up multi_source_correlation task ==="

source /workspace/scripts/task_utils.sh

# ── Clean up ──────────────────────────────────────────────────────────────────
rm -f /tmp/multi_source_result.json /tmp/multi_source_gt.json \
      /tmp/multi_source_start_time 2>/dev/null || true

for d in /home/ga/Cases/Cross_Device_Analysis_2024*/; do
    [ -d "$d" ] && rm -rf "$d" && echo "Removed old case: $d"
done

mkdir -p /home/ga/Reports
chown -R ga:ga /home/ga/Reports/ 2>/dev/null || true

# ── Verify both disk images ───────────────────────────────────────────────────
IMAGE1="/home/ga/evidence/ntfs_undel.dd"
IMAGE2="/home/ga/evidence/jpeg_search.dd"

for IMG in "$IMAGE1" "$IMAGE2"; do
    if [ ! -s "$IMG" ]; then
        echo "ERROR: Disk image not found: $IMG"
        exit 1
    fi
    echo "Disk image: $IMG ($(stat -c%s "$IMG") bytes)"
done

# ── Pre-compute ground truth (MD5 hashes per file in each image) ──────────────
echo "Pre-computing cross-device correlation ground truth..."
python3 << 'PYEOF'
import subprocess, json, re, hashlib, os

IMAGE1 = "/home/ga/evidence/ntfs_undel.dd"
IMAGE2 = "/home/ga/evidence/jpeg_search.dd"

def get_file_hashes(image_path, label):
    """Extract files from image using icat and compute MD5 hashes."""
    # Get file listing
    try:
        fls_result = subprocess.run(
            ["fls", "-r", image_path],
            capture_output=True, text=True, timeout=60
        )
        fls_lines = fls_result.stdout.splitlines()
    except Exception as e:
        print(f"WARNING: fls failed for {label}: {e}")
        fls_lines = []

    # Parse file list
    # fls format: TYPE [*] INODE: NAME  (TYPE can be r/r, -/r, etc.; * = deleted)
    # Nested entries have leading "+ " or "++ "
    files = []
    for line in fls_lines:
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
        if name in ('.', '..') or ':' in name or name.startswith('$'):
            continue
        files.append({"name": name, "inode": inode, "deleted": is_deleted})

    # Compute MD5 for each file
    file_hashes = {}
    for file_info in files:
        try:
            icat_result = subprocess.run(
                ["icat", image_path, file_info["inode"]],
                capture_output=True, timeout=10
            )
            if icat_result.returncode == 0 and icat_result.stdout:
                md5 = hashlib.md5(icat_result.stdout).hexdigest()
                file_hashes[file_info["name"]] = {
                    "md5": md5,
                    "inode": file_info["inode"],
                    "deleted": file_info["deleted"],
                    "size": len(icat_result.stdout)
                }
        except subprocess.TimeoutExpired:
            continue
        except Exception:
            continue

    print(f"{label}: {len(file_hashes)}/{len(files)} files hashed")
    return file_hashes, len(files)

hashes1, total1 = get_file_hashes(IMAGE1, "Source1 (ntfs_undel.dd)")
hashes2, total2 = get_file_hashes(IMAGE2, "Source2 (jpeg_search.dd)")

# Find cross-device matches by MD5
matches = []
md5_to_name1 = {v["md5"]: k for k, v in hashes1.items() if not v["deleted"]}
for name2, info2 in hashes2.items():
    if not info2["deleted"] and info2["md5"] in md5_to_name1:
        name1 = md5_to_name1[info2["md5"]]
        matches.append({
            "md5": info2["md5"],
            "source1_name": name1,
            "source2_name": name2
        })

# Also check full hash set overlap
md5s1 = set(v["md5"] for v in hashes1.values())
md5s2 = set(v["md5"] for v in hashes2.values())
shared_md5s = md5s1 & md5s2

gt = {
    "source1_image": IMAGE1,
    "source2_image": IMAGE2,
    "source1_file_count": total1,
    "source2_file_count": total2,
    "source1_hashed_count": len(hashes1),
    "source2_hashed_count": len(hashes2),
    "source1_md5_count": len(md5s1),
    "source2_md5_count": len(md5s2),
    "cross_device_matches": matches,
    "shared_md5_count": len(shared_md5s),
    "shared_md5s": list(shared_md5s)
}

with open("/tmp/multi_source_gt.json", "w") as f:
    json.dump(gt, f, indent=2)

print(f"Ground truth:")
print(f"  Source1 files: {total1} ({len(hashes1)} hashed)")
print(f"  Source2 files: {total2} ({len(hashes2)} hashed)")
print(f"  Cross-device matches: {len(matches)}")
for m in matches:
    print(f"    {m['md5'][:8]}... {m['source1_name']} <-> {m['source2_name']}")
PYEOF

if [ ! -f /tmp/multi_source_gt.json ]; then
    echo "WARNING: GT computation failed"
    echo '{"source1_file_count":0,"source2_file_count":0,"cross_device_matches":[],"shared_md5_count":0}' \
        > /tmp/multi_source_gt.json
fi

# ── Record start time ─────────────────────────────────────────────────────────
date +%s > /tmp/multi_source_start_time

# ── Launch Autopsy ────────────────────────────────────────────────────────────
kill_autopsy

echo "Launching Autopsy..."
launch_autopsy
wait_for_autopsy_window 300

WELCOME_TIMEOUT=420
WELCOME_ELAPSED=0
WELCOME_FOUND=false
while [ $WELCOME_ELAPSED -lt $WELCOME_TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "welcome"; then
        WELCOME_FOUND=true; break
    fi
    DISPLAY=:1 xdotool mousemove 960 540 click 1 2>/dev/null || true
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 5
    WELCOME_ELAPSED=$((WELCOME_ELAPSED + 5))
    if [ $((WELCOME_ELAPSED % 60)) -eq 0 ]; then
        pgrep -f "/opt/autopsy" >/dev/null 2>&1 || launch_autopsy
    fi
done

if [ "$WELCOME_FOUND" = false ]; then
    kill_autopsy; sleep 2; launch_autopsy
    FINAL_ELAPSED=0
    while [ $FINAL_ELAPSED -lt 120 ]; do
        DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "welcome" && WELCOME_FOUND=true && break
        DISPLAY=:1 xdotool mousemove 960 540 click 1 2>/dev/null || true
        sleep 5; FINAL_ELAPSED=$((FINAL_ELAPSED + 5))
    done
    [ "$WELCOME_FOUND" = false ] && echo "FATAL: Welcome screen never appeared." && exit 1
fi

sleep 3
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

echo "=== Task setup complete ==="
python3 -c "
import json
d = json.load(open('/tmp/multi_source_gt.json'))
print(f\"GT: src1={d.get('source1_file_count',0)} files, src2={d.get('source2_file_count',0)} files, matches={d.get('shared_md5_count',0)}\")
" 2>/dev/null || echo "GT summary unavailable"
