#!/bin/bash
# Setup script for unallocated_string_recovery task

echo "=== Setting up unallocated_string_recovery task ==="

source /workspace/scripts/task_utils.sh

# ── Clean up stale artifacts ──────────────────────────────────────────────────
rm -f /tmp/string_recovery_result.json /tmp/string_recovery_gt.json \
      /tmp/string_recovery_start_time /tmp/task_initial.png 2>/dev/null || true

for d in /home/ga/Cases/String_Recovery_2024*/; do
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

# ── Pre-compute GT for unallocated strings ────────────────────────────────────
echo "Pre-computing GT..."
blkls "$IMAGE" > /tmp/gt_unalloc.bin 2>/dev/null || true
if [ -s /tmp/gt_unalloc.bin ]; then
    UNALLOC_BYTES=$(wc -c < /tmp/gt_unalloc.bin)
    strings -n 6 /tmp/gt_unalloc.bin > /tmp/gt_strings.txt
    TOTAL_STRINGS=$(wc -l < /tmp/gt_strings.txt)
    UNIQUE_STRINGS=$(sort -u /tmp/gt_strings.txt | wc -l)

    # Use grep to approximate string categories
    FILE_PATHS=$(grep -ciE '[/\\]\w+\.\w{2,4}|[A-Z]:\\' /tmp/gt_strings.txt || echo 0)
    URLS=$(grep -ciE 'https?://|www\.|\.com|\.org|\.net' /tmp/gt_strings.txt || echo 0)
    EMAILS=$(grep -ciE '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' /tmp/gt_strings.txt || echo 0)
    NUMERIC=$(grep -cE '^[0-9 .,-]{6,}$' /tmp/gt_strings.txt || echo 0)
    DOC_FRAGS=$(awk 'length>=20 && /[a-zA-Z]{4,}/' /tmp/gt_strings.txt | wc -l || echo 0)
    NTFS_ARTS=$(grep -ciE '\$MFT|\$FILE|NTFS|FILE0|\$DATA|\$INDEX' /tmp/gt_strings.txt || echo 0)

    # Extract some unique sample strings for validation (>8 chars)
    SAMPLES=$(sort -u /tmp/gt_strings.txt | awk 'length>8' | head -20)
else
    UNALLOC_BYTES=0; TOTAL_STRINGS=0; UNIQUE_STRINGS=0; FILE_PATHS=0; URLS=0
    EMAILS=0; NUMERIC=0; DOC_FRAGS=0; NTFS_ARTS=0; SAMPLES=""
fi

# Write GT to JSON securely
python3 << PYEOF
import json
gt = {
  "total_strings": $TOTAL_STRINGS,
  "unique_strings": $UNIQUE_STRINGS,
  "unallocated_bytes": $UNALLOC_BYTES,
  "file_path_count": $FILE_PATHS,
  "url_count": $URLS,
  "email_count": $EMAILS,
  "numeric_count": $NUMERIC,
  "doc_fragment_count": $DOC_FRAGS,
  "ntfs_artifact_count": $NTFS_ARTS,
  "sample_strings": """$SAMPLES""".strip().split('\n') if """$SAMPLES""".strip() else []
}
with open("/tmp/string_recovery_gt.json", "w") as f:
    json.dump(gt, f)
PYEOF

rm -f /tmp/gt_unalloc.bin /tmp/gt_strings.txt
chmod 600 /tmp/string_recovery_gt.json 2>/dev/null || true

# ── Record start time ─────────────────────────────────────────────────────────
date +%s > /tmp/string_recovery_start_time

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

sleep 3
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot proving startup state
take_screenshot /tmp/task_initial.png ga

echo "=== Setup complete ==="