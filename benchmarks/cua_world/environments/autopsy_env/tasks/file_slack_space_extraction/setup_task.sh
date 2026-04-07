#!/bin/bash
echo "=== Setting up file_slack_space_extraction task ==="

source /workspace/scripts/task_utils.sh

# ── Clean up stale artifacts ──────────────────────────────────────────────────
rm -f /tmp/slack_extraction_result.json /tmp/slack_gt.json \
      /tmp/slack_start_time 2>/dev/null || true

mkdir -p /home/ga/Reports
chown -R ga:ga /home/ga/Reports/ 2>/dev/null || true

# ── Ensure write permissions on disk image ────────────────────────────────────
IMAGE="/home/ga/evidence/jpeg_search.dd"
if [ ! -s "$IMAGE" ]; then
    IMAGE="/home/ga/evidence/ntfs_undel.dd"
fi
if [ ! -s "$IMAGE" ]; then
    echo "ERROR: Disk image not found"
    exit 1
fi

chmod 666 "$IMAGE"
echo "Disk image ready: $IMAGE"

# ── Pre-compute Ground Truth and Inject Keys ──────────────────────────────────
echo "Analyzing disk image and injecting Slack Space keys..."
python3 << 'PYEOF'
import subprocess, re, json, sys, os

IMAGE = sys.argv[1] if len(sys.argv) > 1 else "/home/ga/evidence/jpeg_search.dd"
if not os.path.exists(IMAGE):
    IMAGE = "/home/ga/evidence/ntfs_undel.dd"

try:
    fsstat = subprocess.check_output(['fsstat', IMAGE]).decode()
except Exception as e:
    print("fsstat failed:", e)
    sys.exit(1)

# Get the block size (TSK uses this as its unit for 'blocks' or 'sectors' in istat)
block_size_m = re.search(r'Cluster Size:\s*(\d+)', fsstat, re.IGNORECASE)
if not block_size_m:
    block_size_m = re.search(r'Block Size:\s*(\d+)', fsstat, re.IGNORECASE)
if not block_size_m:
    block_size_m = re.search(r'Sector Size:\s*(\d+)', fsstat, re.IGNORECASE)
block_size = int(block_size_m.group(1)) if block_size_m else 512

print(f"Detected block size: {block_size}")

try:
    fls = subprocess.check_output(['fls', '-r', IMAGE]).decode()
except Exception as e:
    print("fls failed:", e)
    sys.exit(1)

jpegs = []
for line in fls.splitlines():
    if ' * ' in line: continue # skip deleted files
    stripped = re.sub(r'^[+\s]+', '', line)
    m = re.match(r'^([\w/-]+)\s+(\d+)(?:-\S+)?:\s+(.+)', stripped)
    if m and m.group(1).endswith('r') and m.group(3).lower().endswith(('.jpg', '.jpeg')):
        name = m.group(3).split('\t')[0].strip()
        jpegs.append({'inode': m.group(2), 'name': name})

valid_jpegs = []
for j in jpegs:
    try:
        istat = subprocess.check_output(['istat', IMAGE, j['inode']]).decode()
        size_m = re.search(r'Size:\s*(\d+)', istat)
        size = int(size_m.group(1)) if size_m else 0

        blocks_match = re.search(r'(?:Sectors|Blocks|Cluster Runs):\n(.*?)(?:\n\n|\Z)', istat, re.DOTALL)
        if not blocks_match: continue

        blocks_str = blocks_match.group(1).replace('\n', ' ')
        blocks = []
        for token in blocks_str.split():
            if '-' in token:
                start, end = token.split('-')
                blocks.extend(range(int(start), int(end)+1))
            elif token.isdigit():
                blocks.append(int(token))

        if not blocks: continue

        slack_bytes = (len(blocks) * block_size) - size
        if 50 < slack_bytes < block_size:
            valid_jpegs.append({
                'name': j['name'],
                'inode': j['inode'],
                'size': size,
                'first_block': blocks[0],
                'last_block': blocks[-1],
                'slack_offset': size % block_size
            })
    except Exception:
        pass

if not valid_jpegs:
    print("WARNING: No valid JPEGs for slack injection. Ground truth will be empty.")
    gt = {}
else:
    # Sort by size to find the smallest allocated JPEG
    valid_jpegs.sort(key=lambda x: x['size'])
    target = valid_jpegs[0]

    true_key = "KEY-TRU-8F9A2C"
    decoy_key1 = "KEY-FALSE-1B3D4E"
    decoy_key2 = "KEY-FALSE-9X8Y7Z"

    try:
        with open(IMAGE, "r+b") as f:
            # Inject True Key into target slack space
            inject_pos = (target['last_block'] * block_size) + target['slack_offset'] + 4
            f.seek(inject_pos)
            f.write(true_key.encode())
            print(f"Injected true key into {target['name']} slack space at offset {inject_pos}")

            # Inject decoy 1 into another file's slack space (if available)
            if len(valid_jpegs) > 1:
                decoy_target = valid_jpegs[-1] # Largest JPEG
                d_pos = (decoy_target['last_block'] * block_size) + decoy_target['slack_offset'] + 4
                f.seek(d_pos)
                f.write(decoy_key1.encode())
                print(f"Injected decoy key 1 into {decoy_target['name']} slack space at offset {d_pos}")

            # Inject decoy 2 at the end of the image (unallocated)
            f.seek(0, 2)
            end_pos = f.tell()
            if end_pos > 2048:
                f.seek(end_pos - 1024)
                f.write(decoy_key2.encode())
                print(f"Injected decoy key 2 into unallocated space near EOF.")

        gt = {
            "target_file": target['name'],
            "logical_size_bytes": target['size'],
            "starting_sector": target['first_block'],
            "extracted_key": true_key
        }
    except Exception as e:
        print("Failed to inject keys:", e)
        gt = {}

with open("/tmp/slack_gt.json", "w") as f:
    json.dump(gt, f, indent=2)

print("Ground truth saved.")
PYEOF "$IMAGE"

chmod 644 /tmp/slack_gt.json 2>/dev/null || true

# ── Record start time ─────────────────────────────────────────────────────────
date +%s > /tmp/slack_start_time

# ── Start Autopsy UI ──────────────────────────────────────────────────────────
echo "Launching Autopsy..."
kill_autopsy
sleep 2
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
    echo "WARNING: Autopsy Welcome screen did NOT appear within ${WELCOME_TIMEOUT}s"
fi

sleep 3
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Dismiss Welcome dialog if it's still focused
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "welcome"; then
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
fi

# Take initial state screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="