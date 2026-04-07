#!/bin/bash
# Setup script for keyword_contraband_search task

echo "=== Setting up keyword_contraband_search task ==="

source /workspace/scripts/task_utils.sh

# ── Clean up ──────────────────────────────────────────────────────────────────
rm -f /tmp/keyword_contraband_result.json /tmp/keyword_contraband_gt.json \
      /tmp/keyword_contraband_start_time 2>/dev/null || true

for d in /home/ga/Cases/Keyword_Search_2024*/; do
    [ -d "$d" ] && rm -rf "$d" && echo "Removed old case: $d"
done

mkdir -p /home/ga/Reports
chown -R ga:ga /home/ga/Reports/ 2>/dev/null || true

# ── Verify disk image ─────────────────────────────────────────────────────────
# Prefer keyword_search.dd (DFTT #11, text-content image for keyword testing)
# Fall back to ntfs_undel.dd if keyword_search.dd not available
IMAGE="/home/ga/evidence/keyword_search.dd"
if [ ! -s "$IMAGE" ]; then
    echo "keyword_search.dd not found, falling back to ntfs_undel.dd"
    IMAGE="/home/ga/evidence/ntfs_undel.dd"
fi
if [ ! -s "$IMAGE" ]; then
    echo "ERROR: No disk image found"
    exit 1
fi
echo "Disk image: $IMAGE ($(stat -c%s "$IMAGE") bytes)"

# ── Pre-compute TSK ground truth (keyword hits using strings/grep) ─────────────
echo "Pre-computing keyword ground truth from image content..."
python3 << 'PYEOF'
import subprocess, json, re, os

IMAGE = "/home/ga/evidence/ntfs_undel.dd"
KEYWORDS = ["secret", "password", "evidence", "deleted"]

# Enumerate all regular files and extract content
try:
    fls_result = subprocess.run(
        ["fls", "-r", IMAGE],
        capture_output=True, text=True, timeout=60
    )
    fls_lines = fls_result.stdout.splitlines()
except Exception as e:
    print(f"WARNING: fls failed: {e}")
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
    # Only regular files
    if type_field.endswith('d') or type_field.endswith('v'):
        continue
    if name in ('.', '..') or ':' in name or name.startswith('$'):
        continue
    files.append({"name": name, "inode": inode, "deleted": is_deleted})

# For each file, extract content and search for keywords
keyword_hits = {kw: [] for kw in KEYWORDS}
files_searched = 0

for file_info in files:
    try:
        icat_result = subprocess.run(
            ["icat", IMAGE, file_info["inode"]],
            capture_output=True, timeout=5
        )
        if icat_result.returncode != 0:
            continue
        # Decode safely, ignoring errors
        content = icat_result.stdout.decode("utf-8", errors="ignore").lower()
        if not content.strip():
            continue
        files_searched += 1
        for kw in KEYWORDS:
            if kw.lower() in content:
                # Find context
                idx = content.find(kw.lower())
                start = max(0, idx - 30)
                end = min(len(content), idx + 70)
                ctx = content[start:end].replace("\n", " ").replace("\r", " ")
                keyword_hits[kw].append({
                    "name": file_info["name"],
                    "inode": file_info["inode"],
                    "deleted": file_info["deleted"],
                    "context": ctx[:100]
                })
    except subprocess.TimeoutExpired:
        continue
    except Exception:
        continue

# Also run strings on entire image for deleted file content
try:
    strings_result = subprocess.run(
        ["strings", IMAGE],
        capture_output=True, text=True, timeout=30
    )
    image_strings = strings_result.stdout.lower()
    for kw in KEYWORDS:
        kw_in_image = kw.lower() in image_strings
        print(f"  Keyword '{kw}' found in raw image strings: {kw_in_image}")
except Exception as e:
    print(f"  strings command failed: {e}")
    image_strings = ""

gt = {
    "keywords_searched": KEYWORDS,
    "keyword_hits": keyword_hits,
    "keywords_with_hits": [kw for kw, hits in keyword_hits.items() if hits],
    "files_searched": files_searched,
    "total_files": len(files),
    "image_path": IMAGE
}

with open("/tmp/keyword_contraband_gt.json", "w") as f:
    json.dump(gt, f, indent=2)

print(f"Ground truth: searched {files_searched}/{len(files)} files")
for kw, hits in keyword_hits.items():
    print(f"  '{kw}': {len(hits)} file(s) hit")
    for h in hits:
        print(f"    -> {h['name']} (inode {h['inode']})")
PYEOF

if [ ! -f /tmp/keyword_contraband_gt.json ]; then
    echo "WARNING: GT computation failed"
    echo '{"keywords_searched":["secret","password","evidence","deleted"],"keyword_hits":{},"keywords_with_hits":[],"files_searched":0}' \
        > /tmp/keyword_contraband_gt.json
fi

# ── Record start time ─────────────────────────────────────────────────────────
date +%s > /tmp/keyword_contraband_start_time

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
echo "GT keywords_with_hits: $(python3 -c "import json; d=json.load(open('/tmp/keyword_contraband_gt.json')); print(d.get('keywords_with_hits', []))" 2>/dev/null || echo '?')"
