#!/bin/bash
echo "=== Setting up mt_cyb_alternative_translation task ==="

# 1. Clean previous state
rm -rf /home/ga/UGENE_Data/mitochondrial 2>/dev/null || true
rm -rf /home/ga/UGENE_Data/results 2>/dev/null || true
mkdir -p /home/ga/UGENE_Data/mitochondrial
mkdir -p /home/ga/UGENE_Data/results

# 2. Fetch the real Human MT-CYB DNA sequence from NCBI
# Using NC_012920.1 coordinates 14747-15887 (MT-CYB locus)
echo "Downloading real human MT-CYB sequence from NCBI..."
curl -sL "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=nuccore&id=NC_012920.1&rettype=fasta&seq_start=14747&seq_stop=15887" > /home/ga/UGENE_Data/mitochondrial/human_mt_cyb.fasta

# Fallback mechanism if NCBI is unreachable
if [ ! -s /home/ga/UGENE_Data/mitochondrial/human_mt_cyb.fasta ] || ! grep -q "^>" /home/ga/UGENE_Data/mitochondrial/human_mt_cyb.fasta; then
    echo "NCBI download failed. Using bundled realistic mitochondrial sequence fallback."
    # A realistic 1140bp sequence with TGA (Trp) codons that trigger stops in the standard table
    python3 -c "
fasta = '>NC_012920.1_fallback Homo sapiens mitochondrion MT-CYB\n'
# ATG (M) + 189 repeats of CCCTGA (Pro-Trp in mt, Pro-Stop in std) + TAA (Stop)
seq = 'ATG' + ('CCCTGA' * 189) + 'TAA'
lines = [seq[i:i+70] for i in range(0, len(seq), 70)]
with open('/home/ga/UGENE_Data/mitochondrial/human_mt_cyb.fasta', 'w') as f:
    f.write(fasta + '\n'.join(lines) + '\n')
"
fi

chown -R ga:ga /home/ga/UGENE_Data/mitochondrial
chown -R ga:ga /home/ga/UGENE_Data/results

# 3. Record start time for anti-gaming verification
date +%s > /tmp/mt_cyb_start_ts

# 4. Kill any existing UGENE instance
pkill -f "ugene" 2>/dev/null || true
sleep 3
pkill -9 -f "ugene" 2>/dev/null || true
sleep 2

# 5. Launch UGENE
echo "Launching UGENE..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid /home/ga/launch_ugene.sh &"

# 6. Wait for UGENE window to appear
TIMEOUT=60
ELAPSED=0
STARTED=false
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "ugene\|UGENE\|Unipro"; then
        echo "UGENE window detected after ${ELAPSED}s"
        STARTED=true
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

if [ "$STARTED" = true ]; then
    sleep 5
    # Dismiss any startup dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1

    # Maximize and focus the UGENE window
    WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ugene\|UGENE\|Unipro" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
        sleep 2
    fi
    
    # Take initial screenshot
    DISPLAY=:1 scrot /tmp/task_start_screenshot.png 2>/dev/null || true
else
    echo "WARNING: UGENE window not detected."
fi

echo "=== Task setup complete ==="