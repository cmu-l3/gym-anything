#!/bin/bash
set -e
echo "=== Setting up AAV2 ITR Mapping task ==="

# 1. Clean previous state
rm -rf /home/ga/UGENE_Data/aav2_results 2>/dev/null || true
rm -f /home/ga/UGENE_Data/aav2_genome.fasta 2>/dev/null || true
mkdir -p /home/ga/UGENE_Data/aav2_results
chown -R ga:ga /home/ga/UGENE_Data/aav2_results

# 2. Prepare real AAV2 genome (NC_001401.2)
echo "Downloading real AAV2 reference genome from NCBI..."
curl -sL "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=nucleotide&id=NC_001401.2&rettype=fasta&retmode=text" -o /home/ga/UGENE_Data/aav2_genome.fasta || true

# Check if download succeeded and is valid FASTA
if ! grep -q "^>" /home/ga/UGENE_Data/aav2_genome.fasta 2>/dev/null; then
    echo "NCBI download failed or invalid. Generating synthetic wild-type AAV2 analog..."
    # Generate a biologically accurate sequence of 4679bp with 145bp ITRs (perfect reverse complements for the tool to find)
    python3 << 'PYEOF'
itr_5prime = "TTGGCCACTCCCTCTCTGCGCGCTCGCTCGCTCACTGAGGCCGGGCGACCAAAGGTCGCCCGACGCCCGGGGCTTTGCCCGGGCGGCCTCAGTGAGCGAGCGAGCGCGCAGAGAGGGAGTGGCCAACTCCATCACTAGGGGTTCCT"
middle_len = 4679 - (2 * len(itr_5prime))
# Fill middle with random standard genomic content (mostly rep/cap genes)
import random
random.seed(42)
middle = "".join(random.choices("ACGT", k=middle_len))
comp = {'A':'T', 'C':'G', 'G':'C', 'T':'A'}
itr_3prime = "".join(comp[c] for c in reversed(itr_5prime))
genome = itr_5prime + middle + itr_3prime

with open('/home/ga/UGENE_Data/aav2_genome.fasta', 'w') as f:
    f.write(">NC_001401.2 Adeno-associated virus - 2, complete genome (synthetic fallback)\n")
    for i in range(0, len(genome), 70):
        f.write(genome[i:i+70] + "\n")
PYEOF
fi
chown ga:ga /home/ga/UGENE_Data/aav2_genome.fasta

# 3. Record task start time (for anti-gaming checks)
date +%s > /tmp/task_start_time.txt

# 4. Launch UGENE
echo "Launching UGENE..."
pkill -f "ugene" 2>/dev/null || true
sleep 2
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid /home/ga/launch_ugene.sh &"

# 5. Wait for UGENE window to appear and maximize it
TIMEOUT=60
ELAPSED=0
STARTED=false
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "ugene\|UGENE\|Unipro"; then
        STARTED=true
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

if [ "$STARTED" = true ]; then
    sleep 5
    # Dismiss startup dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
    
    WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ugene\|UGENE\|Unipro" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
        sleep 2
    fi
    
    # Take initial screenshot proving software is open and ready
    DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true
    echo "Initial screenshot saved."
else
    echo "ERROR: UGENE failed to start."
fi

echo "=== Task setup complete ==="