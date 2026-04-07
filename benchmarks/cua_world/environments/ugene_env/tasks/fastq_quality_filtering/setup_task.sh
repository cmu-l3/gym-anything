#!/bin/bash
set -e
echo "=== Setting up fastq_quality_filtering task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Clean directories
rm -rf /home/ga/UGENE_Data/ngs/results 2>/dev/null || true
mkdir -p /home/ga/UGENE_Data/ngs/results
mkdir -p /home/ga/UGENE_Data/ngs

# Download real Illumina FASTQ dataset (Small viral subset from nf-core test datasets)
echo "Downloading real Illumina FASTQ dataset..."
if [ ! -s /home/ga/UGENE_Data/ngs/raw_reads.fastq ]; then
    curl -sL --retry 3 "https://raw.githubusercontent.com/nf-core/test-datasets/viralrecon/illumina/amplicon/SRR10903401_1.fastq.gz" | gzip -d > /home/ga/UGENE_Data/ngs/raw_reads.fastq || true
fi

# Inject definitively bad reads to ensure the quality filter will have an effect
# ASCII '!' represents Phred Quality 0
for i in {1..250}; do
    echo "@INJECTED_BAD_READ_${i}" >> /home/ga/UGENE_Data/ngs/raw_reads.fastq
    echo "ACGTACGTACGTACGTACGTACGTACGTACGT" >> /home/ga/UGENE_Data/ngs/raw_reads.fastq
    echo "+" >> /home/ga/UGENE_Data/ngs/raw_reads.fastq
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" >> /home/ga/UGENE_Data/ngs/raw_reads.fastq
done

# Ensure permissions are correct
chown -R ga:ga /home/ga/UGENE_Data/ngs

# Ensure UGENE is running and focused
pkill -f "ugene" 2>/dev/null || true
sleep 2

su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid /home/ga/launch_ugene.sh &"

# Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "ugene\|UGENE\|Unipro"; then
        break
    fi
    sleep 1
done

# Give UI time to stabilize and clear dialogs
sleep 5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Maximize window
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ugene\|UGENE\|Unipro" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi
sleep 2

# Take screenshot of initial state (for evidence)
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="