#!/bin/bash
# Setup script for cross_case_central_repository task

echo "=== Setting up cross_case_central_repository task ==="

source /workspace/scripts/task_utils.sh

# ── Clean up stale artifacts and reset Central Repository ─────────────────────
rm -f /tmp/cross_case_result.json /tmp/shared_md5.txt /tmp/cross_case_start_time 2>/dev/null || true

echo "Removing old cases and central repository databases..."
rm -rf /home/ga/Cases/* 2>/dev/null || true
find /home/ga -name "*.db" -type f -delete 2>/dev/null || true
rm -rf /home/ga/.autopsy/dev/config/CentralRepository 2>/dev/null || true
rm -rf /home/ga/.autopsy/dev/central_repository 2>/dev/null || true

mkdir -p /home/ga/Reports
mkdir -p /home/ga/evidence
chown -R ga:ga /home/ga/Reports/ /home/ga/evidence/ 2>/dev/null || true

# ── Generate Dynamic Evidence (Anti-Gaming) ───────────────────────────────────
echo "Generating dynamic evidence images with randomized shared files..."

# 1. Create a unique shared file (so the MD5 cannot be guessed/hardcoded)
head -c 1024 /dev/urandom > /tmp/shared_base.dat
# Add some readable strings just in case Autopsy indexes it
echo "CONFIDENTIAL: Operation dark storm financial records." >> /tmp/shared_base.dat
echo "ID: $RANDOM-$RANDOM" >> /tmp/shared_base.dat
cp /tmp/shared_base.dat /tmp/shared_evidence.pdf

SHARED_MD5=$(md5sum /tmp/shared_evidence.pdf | awk '{print $1}')
echo "$SHARED_MD5" > /tmp/shared_md5.txt
echo "Injected Shared MD5: $SHARED_MD5"

# 2. Create distinct decoy files for each image
head -c 2048 /dev/urandom > /tmp/distinct_alpha.pdf
echo "ALPHA_DECOY_$RANDOM" >> /tmp/distinct_alpha.pdf

head -c 3072 /dev/urandom > /tmp/distinct_beta.pdf
echo "BETA_DECOY_$RANDOM" >> /tmp/distinct_beta.pdf

# 3. Create FAT filesystems and inject the files
# Image 1: Alpha
dd if=/dev/zero of=/home/ga/evidence/suspect_alpha.dd bs=1M count=5 2>/dev/null
mkfs.vfat /home/ga/evidence/suspect_alpha.dd >/dev/null 2>&1
mcopy -i /home/ga/evidence/suspect_alpha.dd /tmp/shared_evidence.pdf ::financial_records.pdf
mcopy -i /home/ga/evidence/suspect_alpha.dd /tmp/distinct_alpha.pdf ::alpha_system.pdf

# Image 2: Beta
dd if=/dev/zero of=/home/ga/evidence/suspect_beta.dd bs=1M count=5 2>/dev/null
mkfs.vfat /home/ga/evidence/suspect_beta.dd >/dev/null 2>&1
mcopy -i /home/ga/evidence/suspect_beta.dd /tmp/shared_evidence.pdf ::stolen_financials.pdf
mcopy -i /home/ga/evidence/suspect_beta.dd /tmp/distinct_beta.pdf ::beta_system.pdf

chown ga:ga /home/ga/evidence/*.dd

# ── Record task start time ────────────────────────────────────────────────────
date +%s > /tmp/cross_case_start_time
echo "Task start time recorded: $(cat /tmp/cross_case_start_time)"

# ── Launch Autopsy ────────────────────────────────────────────────────────────
kill_autopsy
echo "Launching Autopsy..."
launch_autopsy
wait_for_autopsy_window 300

echo "Task Setup Complete."