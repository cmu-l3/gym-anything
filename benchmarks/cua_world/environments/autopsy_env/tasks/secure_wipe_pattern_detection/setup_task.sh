#!/bin/bash
echo "=== Setting up secure_wipe_pattern_detection task ==="

source /workspace/scripts/task_utils.sh

# ── Clean up stale artifacts ──────────────────────────────────────────────────
rm -f /tmp/secure_wipe_result.json /tmp/wiped_files_gt.json \
      /tmp/secure_wipe_start_time 2>/dev/null || true

for d in /home/ga/Cases/Spoliation_Investigation_2024*/; do
    [ -d "$d" ] && rm -rf "$d" && echo "Removed old case: $d"
done

mkdir -p /home/ga/Reports
chown -R ga:ga /home/ga/Reports/ 2>/dev/null || true

# ── Generate Authentic Wiped Evidence Disk Image ──────────────────────────────
echo "Generating FAT32 evidence image with wiped and intact deleted files..."

IMAGE="/home/ga/evidence/wiped_evidence.dd"
mkdir -p /home/ga/evidence
rm -f "$IMAGE"

# Create a 32MB zero-filled file
dd if=/dev/zero of="$IMAGE" bs=1M count=32 2>/dev/null
# Format as FAT32
mkfs.vfat -F 32 -n "SPOLIATION" "$IMAGE" 2>/dev/null

# Create a staging directory for files
STAGING="/tmp/spoliation_staging"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cd "$STAGING" || exit 1

# 1. Intact Files
echo "These are the secret operational notes. Do not share." > notes.txt
echo "admin:supersecret123\nroot:toor" > passwords.log
echo "Meeting confirmed at dock 4, midnight." > itinerary.doc

# 2. Zero-Wiped Files
dd if=/dev/zero of=bank_statements.csv bs=1024 count=12 2>/dev/null
dd if=/dev/zero of=crypto_keys.txt bs=1024 count=4 2>/dev/null
dd if=/dev/zero of=contacts.db bs=1024 count=8 2>/dev/null

# 3. FF-Wiped Files
python3 -c "open('tax_returns.pdf', 'wb').write(b'\xFF' * 15000)"
python3 -c "open('offshore_accounts.xlsx', 'wb').write(b'\xFF' * 8000)"
python3 -c "open('incriminating_photo.jpg', 'wb').write(b'\xFF' * 25000)"

# Copy files into the FAT32 image using mtools
mcopy -i "$IMAGE" notes.txt passwords.log itinerary.doc ::
mcopy -i "$IMAGE" bank_statements.csv crypto_keys.txt contacts.db ::
mcopy -i "$IMAGE" tax_returns.pdf offshore_accounts.xlsx incriminating_photo.jpg ::

# Delete the files using mtools (marks as deleted, payload remains intact on disk)
mdel -i "$IMAGE" ::notes.txt ::passwords.log ::itinerary.doc
mdel -i "$IMAGE" ::bank_statements.csv ::crypto_keys.txt ::contacts.db
mdel -i "$IMAGE" ::tax_returns.pdf ::offshore_accounts.xlsx ::incriminating_photo.jpg

chown ga:ga "$IMAGE"
cd /
rm -rf "$STAGING"

# ── Create Ground Truth JSON ──────────────────────────────────────────────────
cat > /tmp/wiped_files_gt.json << 'EOF'
{
  "INTACT": ["notes.txt", "passwords.log", "itinerary.doc"],
  "WIPED_ZERO": ["bank_statements.csv", "crypto_keys.txt", "contacts.db"],
  "WIPED_FF": ["tax_returns.pdf", "offshore_accounts.xlsx", "incriminating_photo.jpg"]
}
EOF
chmod 644 /tmp/wiped_files_gt.json
echo "Evidence image and Ground Truth created."

# ── Record task start time ────────────────────────────────────────────────────
date +%s > /tmp/secure_wipe_start_time

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

if [ "$WELCOME_FOUND" = false ]; then
    kill_autopsy; sleep 2; launch_autopsy
    FINAL_ELAPSED=0
    while [ $FINAL_ELAPSED -lt 120 ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "welcome"; then
            WELCOME_FOUND=true; break
        fi
        DISPLAY=:1 xdotool mousemove 960 540 click 1 2>/dev/null || true
        sleep 5; FINAL_ELAPSED=$((FINAL_ELAPSED + 5))
    done
fi

sleep 3
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="