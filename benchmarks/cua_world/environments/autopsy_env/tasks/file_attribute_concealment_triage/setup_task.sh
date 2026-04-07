#!/bin/bash
# Setup script for file_attribute_concealment_triage task

echo "=== Setting up file_attribute_concealment_triage task ==="

source /workspace/scripts/task_utils.sh

# ── Clean up stale artifacts ──────────────────────────────────────────────────
rm -f /tmp/concealment_result.json /tmp/concealment_gt.json \
      /tmp/concealment_start_time /tmp/task_initial.png 2>/dev/null || true

for d in /home/ga/Cases/Concealed_Evidence_2024*/; do
    [ -d "$d" ] && rm -rf "$d" && echo "Removed old case: $d"
done

mkdir -p /home/ga/Reports/hidden_exports
chown -R ga:ga /home/ga/Reports/ 2>/dev/null || true

# ── Create FAT image with hidden files ────────────────────────────────────────
IMAGE="/home/ga/evidence/hidden_files.dd"
echo "Creating FAT image: $IMAGE"

dd if=/dev/zero of="$IMAGE" bs=1M count=10 2>/dev/null
mkfs.vfat -F 32 -n "SUSPECTUSB" "$IMAGE" 2>/dev/null

# Create dummy files using 8.3 filenames to avoid VFAT complexities
cat << 'EOF' > /tmp/finances.csv
DATE,ACCOUNT,AMOUNT,NOTES
2023-01-15,OFFSHORE_A,50000,Transfer
2023-02-20,OFFSHORE_B,75000,Payment
EOF

cat << 'EOF' > /tmp/password.txt
protonmail: suspect@proton.me / hidd3n_p4ssw0rd!
crypto_wallet: 12 words seed phrase ...
EOF

echo "Standard vacation photo data..." > /tmp/vacation.jpg
echo "Software backup config file..." > /tmp/config.bak
echo "System log..." > /tmp/syslog.txt
echo "Receipt for software..." > /tmp/receipt.pdf

mcopy -i "$IMAGE" /tmp/finances.csv ::/
mcopy -i "$IMAGE" /tmp/password.txt ::/
mcopy -i "$IMAGE" /tmp/vacation.jpg ::/
mcopy -i "$IMAGE" /tmp/config.bak ::/
mcopy -i "$IMAGE" /tmp/syslog.txt ::/
mcopy -i "$IMAGE" /tmp/receipt.pdf ::/

# Set DOS hidden attribute (+h) on the contraband files
mattrib -i "$IMAGE" +h ::/finances.csv
mattrib -i "$IMAGE" +h ::/password.txt

chown ga:ga "$IMAGE"

# ── Pre-compute TSK ground truth ──────────────────────────────────────────────
echo "Pre-computing ground truth from TSK..."
python3 << 'PYEOF'
import subprocess, json, re, hashlib

IMAGE = "/home/ga/evidence/hidden_files.dd"

try:
    result = subprocess.run(["fls", "-r", IMAGE], capture_output=True, text=True, timeout=10)
    lines = result.stdout.splitlines()
except Exception as e:
    print(f"fls failed: {e}")
    lines = []

files = []
for line in lines:
    stripped = re.sub(r'^[+\s]+', '', line)
    m = re.match(r'^([\w/-]+)\s+(?:\*\s+)?(\d+)(?:-\S+)?:\s+(.+)', stripped)
    if not m: continue
    type_field, inode, name = m.groups()
    name = name.split('\t')[0].strip()
    
    # Exclude directories, special files, and volume labels
    if type_field.endswith('d') or type_field.endswith('v'): continue
    if name in ('.', '..') or name.startswith('$'): continue
    
    files.append({"name": name, "inode": inode})

hidden_files = []
normal_files = []

for f in files:
    res = subprocess.run(["istat", IMAGE, f["inode"]], capture_output=True, text=True)
    out = res.stdout
    # Check if istat output indicates the file has the Hidden attribute
    if "Attributes:" in out and "Hidden" in out:
        hidden_files.append(f)
    else:
        normal_files.append(f)

# Compute hashes for all files
for f in hidden_files + normal_files:
    res = subprocess.run(["icat", IMAGE, f["inode"]], capture_output=True)
    if res.returncode == 0:
        f["md5"] = hashlib.md5(res.stdout).hexdigest()
        f["size"] = len(res.stdout)

gt = {
    "hidden_files": hidden_files,
    "normal_files": normal_files,
    "total_hidden": len(hidden_files),
    "total_normal": len(normal_files),
    "hidden_names": [f["name"] for f in hidden_files],
    "normal_names": [f["name"] for f in normal_files]
}

with open("/tmp/concealment_gt.json", "w") as f:
    json.dump(gt, f, indent=2)

print(f"GT: {len(hidden_files)} hidden files, {len(normal_files)} normal files")
PYEOF

# ── Record task start time ────────────────────────────────────────────────────
date +%s > /tmp/concealment_start_time

# ── Launch Autopsy ────────────────────────────────────────────────────────────
kill_autopsy
echo "Launching Autopsy..."
launch_autopsy
wait_for_autopsy_window 300

# Wait briefly for UI to stabilize and dismiss standard startup dialogs
sleep 15
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Maximize Autopsy window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "autopsy" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot showing Autopsy ready state
take_screenshot /tmp/task_initial.png ga

echo "=== Task setup complete ==="