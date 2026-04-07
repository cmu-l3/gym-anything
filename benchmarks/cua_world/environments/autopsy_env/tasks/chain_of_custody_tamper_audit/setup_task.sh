#!/bin/bash
# Setup script for chain_of_custody_tamper_audit task

echo "=== Setting up chain_of_custody_tamper_audit task ==="

source /workspace/scripts/task_utils.sh

# ── Clean up stale artifacts ──────────────────────────────────────────────────
rm -f /tmp/chain_of_custody_result.json /tmp/chain_of_custody_gt.json \
      /tmp/chain_of_custody_start_time 2>/dev/null || true

for d in /home/ga/Cases/Evidence_Audit_2024*/; do
    [ -d "$d" ] && rm -rf "$d" && echo "Removed old case: $d"
done

mkdir -p /home/ga/evidence
mkdir -p /home/ga/Reports
chown ga:ga /home/ga/evidence /home/ga/Reports

# ── Generate realistic data files for FAT32 injection ─────────────────────────
mkdir -p /tmp/benign
mkdir -p /tmp/planted

# Use real system files to avoid synthetic placeholder data
cp /etc/services /tmp/benign/services_log.txt 2>/dev/null || echo "Real service data fallback" > /tmp/benign/services_log.txt
cp /etc/os-release /tmp/benign/system_info.txt 2>/dev/null || echo "System release info fallback" > /tmp/benign/system_info.txt

# Touch benign files to pre-date the seizure (Seizure Date: 2023-05-01)
touch -t 202201011000 /tmp/benign/services_log.txt
touch -t 202201011000 /tmp/benign/system_info.txt

# Planted files with timestamps AFTER the seizure
cp /var/log/dpkg.log /tmp/planted/planted_evidence.txt 2>/dev/null || echo "Incriminating evidence logs" > /tmp/planted/planted_evidence.txt
# Find a real image file on the system to act as the planted image
IMAGE_SRC=$(find /usr/share/icons -name "*.png" -type f | head -1)
if [ -n "$IMAGE_SRC" ]; then
    cp "$IMAGE_SRC" /tmp/planted/confidential_informant.png
else
    echo "Dummy image data" > /tmp/planted/confidential_informant.png
fi

touch -t 202308151000 /tmp/planted/planted_evidence.txt
touch -t 202308151000 /tmp/planted/confidential_informant.png

# ── Create FAT32 Images ───────────────────────────────────────────────────────
echo "Creating evidence disk images..."
for i in 1 2 3; do
    IMG="/home/ga/evidence/seized_usb_${i}.dd"
    # Create a 10MB image
    dd if=/dev/zero of="$IMG" bs=1M count=10 2>/dev/null
    mkfs.vfat "$IMG" >/dev/null 2>&1
    
    # Inject benign files preserving their older timestamps
    MTOOLS_SKIP_CHECK=1 mcopy -i "$IMG" -m /tmp/benign/services_log.txt ::/services_log.txt
    MTOOLS_SKIP_CHECK=1 mcopy -i "$IMG" -m /tmp/benign/system_info.txt ::/system_info.txt
    
    chown ga:ga "$IMG"
done

# Calculate original hashes
HASH1=$(sha256sum /home/ga/evidence/seized_usb_1.dd | awk '{print $1}')
HASH2=$(sha256sum /home/ga/evidence/seized_usb_2.dd | awk '{print $1}')
HASH3=$(sha256sum /home/ga/evidence/seized_usb_3.dd | awk '{print $1}')

# Write acquisition log
cat > /home/ga/evidence/Chain_of_Custody_Log.txt << EOF
CHAIN OF CUSTODY & ACQUISITION LOG
==================================
Case: IA-001 Internal Audit
Seizure Date: 2023-05-01 00:00:00 UTC
Acquisition Officer: Det. Smith

EVIDENCE HASHES (SHA-256) AT TIME OF SEIZURE:
seized_usb_1.dd: $HASH1
seized_usb_2.dd: $HASH2
seized_usb_3.dd: $HASH3

Notes: All drives acquired and sealed in evidence locker #42 on Seizure Date.
EOF
chown ga:ga /home/ga/evidence/Chain_of_Custody_Log.txt

# ── Introduce Tampering (Anti-Gaming) ─────────────────────────────────────────
# Randomly select one image to tamper with
TAMPER_IDX=$(( (RANDOM % 3) + 1 ))
TAMPER_IMG="/home/ga/evidence/seized_usb_${TAMPER_IDX}.dd"
echo "Tampering with $TAMPER_IMG (Hidden from agent)..."

# Inject planted files into the selected tampered image
MTOOLS_SKIP_CHECK=1 mcopy -i "$TAMPER_IMG" -m /tmp/planted/planted_evidence.txt ::/planted_evidence.txt
MTOOLS_SKIP_CHECK=1 mcopy -i "$TAMPER_IMG" -m /tmp/planted/confidential_informant.png ::/confidential_informant.png

# Calculate new hash
NEW_HASH=$(sha256sum "$TAMPER_IMG" | awk '{print $1}')

# Determine the original hash of the tampered image
if [ $TAMPER_IDX -eq 1 ]; then ORIG_HASH=$HASH1; fi
if [ $TAMPER_IDX -eq 2 ]; then ORIG_HASH=$HASH2; fi
if [ $TAMPER_IDX -eq 3 ]; then ORIG_HASH=$HASH3; fi

# Write ground truth for the verifier
cat > /tmp/chain_of_custody_gt.json << EOF
{
  "tampered_image": "seized_usb_${TAMPER_IDX}.dd",
  "original_hash": "$ORIG_HASH",
  "current_hash": "$NEW_HASH",
  "planted_files": ["planted_evidence.txt", "confidential_informant.png"]
}
EOF
chown root:root /tmp/chain_of_custody_gt.json
chmod 600 /tmp/chain_of_custody_gt.json

# ── Record task start time ────────────────────────────────────────────────────
date +%s > /tmp/chain_of_custody_start_time

# ── Launch Autopsy and wait for Welcome screen ────────────────────────────────
kill_autopsy
echo "Launching Autopsy..."
launch_autopsy

wait_for_autopsy_window 300

# Additional logic to ensure Welcome Screen is present
WELCOME_TIMEOUT=420
WELCOME_ELAPSED=0
WELCOME_FOUND=false
while [ $WELCOME_ELAPSED -lt $WELCOME_TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "welcome"; then
        WELCOME_FOUND=true
        break
    fi
    DISPLAY=:1 xdotool mousemove 960 540 click 1 2>/dev/null || true
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 5
    WELCOME_ELAPSED=$((WELCOME_ELAPSED + 5))
    if [ $((WELCOME_ELAPSED % 60)) -eq 0 ]; then
        if ! pgrep -f "/opt/autopsy" >/dev/null 2>&1; then
            launch_autopsy
        fi
    fi
done

if [ "$WELCOME_FOUND" = false ]; then
    kill_autopsy
    sleep 2
    launch_autopsy
fi

sleep 3
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Maximize Autopsy if visible
WID=$(DISPLAY=:1 wmctrl -l | grep -i "autopsy" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="