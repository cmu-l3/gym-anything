#!/bin/bash
# Setup script for custom_magic_signature_identification task

echo "=== Setting up custom_magic_signature_identification task ==="

source /workspace/scripts/task_utils.sh

# ── Clean up stale artifacts ──────────────────────────────────────────────────
rm -f /tmp/c2_hunting_result.json /tmp/c2_hunting_gt.json \
      /tmp/c2_hunting_start_time 2>/dev/null || true

for d in /home/ga/Cases/C2_Hunting_2024*/; do
    [ -d "$d" ] && rm -rf "$d" && echo "Removed old case: $d"
done

mkdir -p /home/ga/Reports
chown -R ga:ga /home/ga/Reports/ 2>/dev/null || true

# ── Generate realistic FAT32 evidence image with injected files ───────────────
echo "Generating synthetic evidence image with obfuscated C2 files..."

IMAGE="/home/ga/evidence/c2_evidence.dd"
mkdir -p /home/ga/evidence

# Create a 20MB raw image
dd if=/dev/zero of="$IMAGE" bs=1M count=20 2>/dev/null
# Format as FAT32
mkfs.vfat -F 32 -n "C2_DRIVE" "$IMAGE" >/dev/null 2>&1

# Generate background noise files
echo "System log active. No errors." > /tmp/syslog.txt
echo "User preferences backup." > /tmp/prefs.dat
echo "GIF89a..." > /tmp/not_a_real_gif.gif

# Generate obfuscated C2 files starting with the magic signature "XYZCONF"
printf "XYZCONF version=1.2\nserver=10.0.0.5\nport=443\n" > /tmp/sys_config.txt
printf "XYZCONF payload=hidden\nkey=abc123\nmode=stealth\n" > /tmp/vacation_photo.jpg
printf "XYZCONF target=all\nmodule=keylogger\n" > /tmp/system_backup.dat

# Copy files into the FAT32 image using mtools
mcopy -i "$IMAGE" /tmp/syslog.txt ::/syslog.txt
mcopy -i "$IMAGE" /tmp/prefs.dat ::/prefs.dat
mcopy -i "$IMAGE" /tmp/not_a_real_gif.gif ::/not_a_real_gif.gif
mcopy -i "$IMAGE" /tmp/sys_config.txt ::/sys_config.txt
mcopy -i "$IMAGE" /tmp/vacation_photo.jpg ::/vacation_photo.jpg
mcopy -i "$IMAGE" /tmp/system_backup.dat ::/system_backup.dat

chown ga:ga "$IMAGE"
chmod 644 "$IMAGE"

echo "Evidence image created at $IMAGE"

# ── Record Ground Truth ───────────────────────────────────────────────────────
cat << 'EOF' > /tmp/c2_hunting_gt.json
{
  "c2_files": [
    "sys_config.txt",
    "vacation_photo.jpg",
    "system_backup.dat"
  ],
  "noise_files": [
    "syslog.txt",
    "prefs.dat",
    "not_a_real_gif.gif"
  ],
  "expected_mime_type": "application/x-xyz-config"
}
EOF
chmod 644 /tmp/c2_hunting_gt.json

# ── Record task start time ────────────────────────────────────────────────────
date +%s > /tmp/c2_hunting_start_time

# ── Launch Autopsy ────────────────────────────────────────────────────────────
kill_autopsy
sleep 2

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
    # Click center screen to help dismiss any generic modal dialogs blocking launch
    DISPLAY=:1 xdotool mousemove 960 540 click 1 2>/dev/null || true
    sleep 5
    WELCOME_ELAPSED=$((WELCOME_ELAPSED + 5))
done

if [ "$WELCOME_FOUND" = false ]; then
    echo "WARNING: Autopsy Welcome screen not clearly detected, proceeding anyway."
fi

# Dismiss Welcome dialog to let agent start clean
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="